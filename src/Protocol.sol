// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";
import { IContinuousInterestIndexing } from "./interfaces/IContinuousInterestIndexing.sol";

import { ContinuousInterestIndexing } from "./ContinuousInterestIndexing.sol";
import { StatelessERC712 } from "./StatelessERC712.sol";

/**
 * @title Protocol
 * @author M^ZERO LABS_
 * @notice Core protocol of M^ZERO ecosystem. TODO Add description.
 */
contract Protocol is IProtocol, ContinuousInterestIndexing, StatelessERC712 {
    // TODO: bit-packing
    struct CollateralBasic {
        uint256 amount;
        uint256 lastUpdated;
        uint256 penalizedUntil; // for missed update collateral intervals only
    }

    // TODO: bit-packing
    struct MintRequest {
        uint256 mintId; // TODO: uint96 or uint48 if 2 additional fields
        address to;
        uint256 amount;
        uint256 createdAt;
    }

    struct CollateralUpdateInfo {
        uint256 amount;
        string metadata;
        uint256[] retrieveIds;
        address[] validators;
        uint256[] timestamps;
        bytes[] signatures;
    }

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256(
            "UpdateCollateral(address minter,uint256 amount,string metadata,uint256[] retrieveIds,uint256 timestamp,)"
        ); // TODO: set constant when finalized

    uint256 public constant ONE = 10_000; // 100% in basis points.

    address public immutable spogRegistrar;
    address public immutable spogVault;
    address public immutable mToken;

    uint256 public totalNormalizedPrincipal;

    uint256 public totalRemovedOutstandingValue;

    mapping(address minter => CollateralBasic basic) public collateralOf;

    mapping(address minter => MintRequest request) public mintRequestOf;

    mapping(address minter => uint256 timestamp) public unfrozenTimeOf;

    mapping(address minter => uint256 amount) public normalizedPrincipalOf;

    mapping(address minter => uint256 amount) public removedOutstandingValueOf;

    mapping(address minter => uint256 amount) public totalRetrieveAmountOf;

    mapping(address minter => mapping(uint256 retrieveId => uint256 amount)) public retrieveRequestOf;

    modifier onlyApprovedMinter() {
        _revertIfNotApprovedMinter(msg.sender);

        _;
    }

    modifier onlyApprovedValidator() {
        _revertIfNotApprovedValidator(msg.sender);

        _;
    }

    /**
     * @notice Constructor.
     * @param spogRegistrar_ The address of the SPOG Registrar contract.
     */
    constructor(address spogRegistrar_, address mToken_) ContinuousInterestIndexing() StatelessERC712("Protocol") {
        if ((spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
        if ((spogVault = SPOGRegistrarReader.getVault(spogRegistrar_)) == address(0)) revert ZeroSpogVault();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    function updateCollateral(
        uint256 amount_,
        string memory metadata_, // TODO: bytes32?
        uint256[] calldata retrieveIds_,
        address[] calldata validators_,
        uint256[] calldata timestamps_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length || signatures_.length != timestamps_.length)
            revert InvalidSignaturesLength();

        address minter_ = msg.sender;

        _closeRetrieveRequests(minter_, retrieveIds_);

        // Validate that quorum of signatures was collected
        uint256 minTimestamp_ = _revertIfInsufficientValidSignatures(
            CollateralUpdateInfo({
                amount: amount_,
                metadata: metadata_,
                retrieveIds: retrieveIds_,
                validators: validators_,
                timestamps: timestamps_,
                signatures: signatures_
            })
        );

        // If minter_ is penalized, total normalized M principal is changing
        updateIndex();

        // Accrue penalty for expired collateral value
        _accruePenaltyForExpiredCollateralValue(minter_);

        _updateCollateralValue(minter_, amount_, minTimestamp_, metadata_);

        // Accrue penalty for maintaining excessive outstanding value
        _accruePenaltyForExcessiveOutstandingValue(minter_);
    }

    function proposeMint(uint256 amount_, address to_) external onlyApprovedMinter returns (uint256) {
        address minter_ = msg.sender;
        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < unfrozenTimeOf[msg.sender]) revert FrozenMinter();

        // Check that mint is sufficiently collateralized
        uint256 allowedOutstandingValue_ = _allowedOutstandingValueOf(minter_);
        uint256 currentOutstandingValue_ = _outstandingValueOf(minter_);
        if (currentOutstandingValue_ + amount_ > allowedOutstandingValue_) revert UndercollateralizedMint();

        uint256 mintId_ = uint256(keccak256(abi.encode(minter_, amount_, to_, now_, gasleft())));

        // Save mint request info
        MintRequest storage mintRequest_ = mintRequestOf[minter_];
        mintRequest_.mintId = mintId_;
        mintRequest_.to = to_;
        mintRequest_.amount = amount_;
        mintRequest_.createdAt = now_;

        emit MintRequestedCreated(mintId_, minter_, amount_, to_);

        return mintId_;
    }

    function mint(uint256 mintId_) external onlyApprovedMinter {
        address minter_ = msg.sender;

        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < unfrozenTimeOf[minter_]) revert FrozenMinter();

        MintRequest storage mintRequest_ = mintRequestOf[minter_];

        // Inconsistent mintId_
        if (mintRequest_.mintId != mintId_) revert InvalidMintRequest();

        // Check that request is executable
        (uint256 amount_, uint256 createdAt_, address to_) = (
            mintRequest_.amount,
            mintRequest_.createdAt,
            mintRequest_.to
        );

        uint256 activeAt_ = createdAt_ + SPOGRegistrarReader.getMintDelay(spogRegistrar);
        if (now_ < activeAt_) revert PendingMintRequest();

        uint256 expiresAt_ = activeAt_ + SPOGRegistrarReader.getMintTTL(spogRegistrar);
        if (now_ > expiresAt_) revert ExpiredMintRequest();

        // Check that mint is sufficiently collateralized
        uint256 allowedOutstandingValue_ = _allowedOutstandingValueOf(minter_);
        uint256 currentOutstandingValue_ = _outstandingValueOf(minter_);
        if (currentOutstandingValue_ + amount_ > allowedOutstandingValue_) revert UndercollateralizedMint();

        updateIndex();

        // Delete mint request
        delete mintRequestOf[minter_];

        // Adjust normalized principal for minter
        uint256 normalizedPrincipal_ = _getPrincipalValue(amount_);
        normalizedPrincipalOf[minter_] += normalizedPrincipal_;
        totalNormalizedPrincipal += normalizedPrincipal_;

        // Mint actual M tokens
        IMToken(mToken).mint(to_, amount_);

        emit MintRequestExecuted(mintId_, minter_, amount_, to_);
    }

    function cancel(uint256 mintId_) external onlyApprovedMinter {
        _cancel(msg.sender, mintId_);
    }

    function retrieve(uint256 amount_) external onlyApprovedMinter returns (uint256) {
        address minter_ = msg.sender;

        uint256 allowedOutstandingValue_ = _allowedOutstandingValueOf(minter_);
        uint256 currentOutstandingValue_ = _outstandingValueOf(minter_);
        if (currentOutstandingValue_ + amount_ > allowedOutstandingValue_) revert UndercollateralizedRetrieve();

        uint256 retrieveId_ = uint256(keccak256(abi.encode(minter_, amount_, block.timestamp, gasleft())));

        collateralOf[minter_].amount -= amount_;
        totalRetrieveAmountOf[minter_] += amount_;
        retrieveRequestOf[minter_][retrieveId_] = amount_;

        emit RetrieveRequestCreated(retrieveId_, minter_, amount_);

        return retrieveId_;
    }

    function burn(address minter_, uint256 amount_) external {
        updateIndex();

        _accruePenaltyForExpiredCollateralValue(minter_);

        uint256 repayAmount_ = SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_)
            ? _repayForActiveMinter(minter_, amount_)
            : _repayForRemovedMinter(minter_, amount_);

        // Burn actual M tokens
        IMToken(mToken).burn(msg.sender, repayAmount_);

        emit Burn(minter_, repayAmount_, msg.sender);
    }

    function _repayForActiveMinter(address minter_, uint256 amount_) internal returns (uint256) {
        uint256 repayAmount_ = _min(_outstandingValueOf(minter_), amount_);
        uint256 repayPrincipal_ = _getPrincipalValue(repayAmount_);

        normalizedPrincipalOf[minter_] -= repayPrincipal_;
        totalNormalizedPrincipal -= repayPrincipal_;

        return repayAmount_;
    }

    function _repayForRemovedMinter(address minter_, uint256 amount_) internal returns (uint256) {
        uint256 repayAmount_ = _min(removedOutstandingValueOf[minter_], amount_);

        removedOutstandingValueOf[minter_] -= repayAmount_;
        totalRemovedOutstandingValue -= repayAmount_;

        return repayAmount_;
    }

    function outstandingValueOf(address minter_) external view returns (uint256) {
        return _outstandingValueOf(minter_);
    }

    function getUnaccruedPenaltyForExpiredCollateralValue(address minter_) external view returns (uint256) {
        return _getUnaccruedPenaltyForExpiredCollateralValue(minter_);
    }

    /******************************************************************************************************************\
    |                                                Validator Functions                                               |
    \******************************************************************************************************************/

    function cancel(address minter_, uint256 mintId_) external onlyApprovedValidator {
        _cancel(minter_, mintId_);
    }

    function freeze(address minter_) external onlyApprovedValidator {
        uint256 frozenUntil_ = block.timestamp + SPOGRegistrarReader.getMinterFreezeTime(spogRegistrar);

        emit MinterFrozen(minter_, unfrozenTimeOf[minter_] = frozenUntil_);
    }

    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/

    function updateIndex()
        public
        override(IContinuousInterestIndexing, ContinuousInterestIndexing)
        returns (uint256 index_)
    {
        // TODO: Order of these matter if their rate models depend on the same utilization ratio / total supplies.
        index_ = super.updateIndex(); // Update Minter index.

        IMToken(mToken).updateIndex(); // Update Earning index.

        // Mint M to Zero Vault
        uint256 excessMintedValue_ = _getExcessMintedValue();

        if (excessMintedValue_ > 0) IMToken(mToken).mint(spogVault, excessMintedValue_);
    }

    function remove(address minter_) external {
        if (SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_)) revert StillApprovedMinter();

        updateIndex();

        // NOTE: Instead of accruing, calculate penalty and add it to `removedOutstandingValueOf` to save gas
        uint256 penalty_ = _getUnaccruedPenaltyForExpiredCollateralValue(minter_);
        uint256 outstandingValueWithPenalty_ = _outstandingValueOf(minter_) + penalty_;

        // NOTE: Do not allow setting removedOutstandingValueOf to 0 by calling this function multiple times
        removedOutstandingValueOf[minter_] += outstandingValueWithPenalty_;
        totalRemovedOutstandingValue += outstandingValueWithPenalty_;

        // Reset minter's state
        delete collateralOf[minter_];
        delete mintRequestOf[minter_];
        delete unfrozenTimeOf[minter_];
        // TODO: delete retrieveRequestOf when this feature is merged

        totalNormalizedPrincipal -= normalizedPrincipalOf[minter_];
        delete normalizedPrincipalOf[minter_];

        emit MinterRemoved(minter_, outstandingValueWithPenalty_, msg.sender);
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _accruePenalty(address minter_, uint256 penaltyBase_) internal {
        uint256 penalty_ = _getPenalty(penaltyBase_);

        uint256 penaltyPrincipal_ = _getPrincipalValue(penalty_);
        normalizedPrincipalOf[minter_] += penaltyPrincipal_;
        totalNormalizedPrincipal += penaltyPrincipal_;

        emit PenaltyAccrued(minter_, penalty_, msg.sender);
    }

    function _accruePenaltyForExpiredCollateralValue(address minter_) internal {
        (uint256 penaltyBase_, uint256 penalizedUntil_) = _getPenaltyBaseAndTimeForExpiredCollateralValue(minter_);

        // Save penalization interval to not double charge for missed periods again
        collateralOf[minter_].penalizedUntil = penalizedUntil_;

        _accruePenalty(minter_, penaltyBase_);
    }

    function _accruePenaltyForExcessiveOutstandingValue(address minter_) internal {
        uint256 allowedOutstandingValue_ = _allowedOutstandingValueOf(minter_);
        uint256 currentOutstandingValue_ = _outstandingValueOf(minter_);

        if (allowedOutstandingValue_ >= currentOutstandingValue_) return;

        _accruePenalty(minter_, currentOutstandingValue_ - allowedOutstandingValue_);
    }

    function _cancel(address minter_, uint256 mintId_) internal {
        if (mintRequestOf[minter_].mintId != mintId_) revert InvalidMintRequest();

        delete mintRequestOf[minter_];

        emit MintRequestCanceled(mintId_, minter_, msg.sender);
    }

    function _closeRetrieveRequests(address minter_, uint256[] calldata retrieveIds_) internal {
        for (uint256 index_ = 0; index_ < retrieveIds_.length; index_++) {
            uint256 retrieveId_ = retrieveIds_[index_];
            uint256 retrieveAmount_ = retrieveRequestOf[minter_][retrieveId_];

            delete retrieveRequestOf[minter_][retrieveId_];
            totalRetrieveAmountOf[minter_] -= retrieveAmount_;

            emit RetrieveRequestClosed(retrieveId_, minter_, retrieveAmount_);
        }
    }

    function _updateCollateralValue(
        address minter_,
        uint256 amount_,
        uint256 lastUpdated_,
        string memory metadata_
    ) internal {
        CollateralBasic storage minterCollateral_ = collateralOf[minter_];

        uint256 amountWithoutRetrieves_ = amount_ - totalRetrieveAmountOf[minter_];

        minterCollateral_.amount = amountWithoutRetrieves_;
        minterCollateral_.lastUpdated = lastUpdated_;

        emit CollateralUpdated(minter_, amount_, amountWithoutRetrieves_, lastUpdated_, metadata_);
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method
     * @param minter_ The address of the minter
     * @param amount_ The amount of collateral
     * @param metadata_ The metadata of the collateral update, reserved for future informational use
     * @param retrieveIds_ The list of retrieve request IDs to close
     * @param timestamp_ The timestamp of the collateral update
     */
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256[] memory retrieveIds_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return
            _getDigest(
                keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, retrieveIds_, timestamp_))
            );
    }

    function _getExcessMintedValue() internal view returns (uint256 excessMintedValue_) {
        uint256 totalSupply_ = IMToken(mToken).totalSupply();
        uint256 totalOutstandingValue_ = _getOutstandingValue(totalNormalizedPrincipal);

        if (totalOutstandingValue_ > totalSupply_) return totalOutstandingValue_ - totalSupply_;
    }

    // /**
    //  * @notice Checks that enough valid unique signatures were provided
    //  * @param amount_ The amount of collateral
    //  * @param metadata_ The metadata of the collateral update, reserved for future informational use
    //  * @param retrieveIds_ The list of retrieve request IDs to close
    //  * @param validators_ The list of validators
    //  * @param timestamps_ The list of validator timestamps for the collateral update signatures
    //  * @param signatures_ The list of signatures
    //  * @return The minimum timestamp between all valid timestamps for valid signatures
    //  */
    /**
     * @notice Checks that enough valid unique signatures were provided
     * @param info_ The information about the collateral update
     * @return The minimum of all timestamps for valid signatures
     */
    function _revertIfInsufficientValidSignatures(CollateralUpdateInfo memory info_) internal view returns (uint256) {
        uint256 requiredQuorum_ = SPOGRegistrarReader.getUpdateCollateralQuorum(spogRegistrar);
        if (info_.validators.length < requiredQuorum_) revert NotEnoughValidSignatures();

        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        uint256 lastUpdated_ = collateralOf[msg.sender].lastUpdated;

        uint256 validSignaturesNum_ = 0;
        uint256 minTimestamp_ = info_.timestamps[0];

        for (uint256 index_ = 0; index_ < info_.signatures.length; index_++) {
            // Check that validator address is unique and is not already accounted for
            address validator_ = info_.validators[index_];
            uint256 timestamp_ = info_.timestamps[index_];

            if (index_ > 0 && validator_ <= info_.validators[index_ - 1]) continue; // duplicate

            if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_)) continue; // not approved

            // Timestamp time range sanity checks
            if (block.timestamp > timestamp_ + updateInterval_) continue; // expired timestamp
            if (lastUpdated_ > timestamp_) continue; // stale timestamp

            // Check that ECDSA or ERC1271 signatures for given digest are valid
            bytes32 digest_ = _getUpdateCollateralDigest(
                msg.sender,
                info_.amount,
                info_.metadata,
                info_.retrieveIds,
                timestamp_
            );
            if (!SignatureChecker.isValidSignature(validator_, digest_, info_.signatures[index_])) continue;

            // Find minimum timestamp for valid signatures
            minTimestamp_ = _min(minTimestamp_, info_.timestamps[index_]);

            // Stop processing if quorum was reached
            if (++validSignaturesNum_ == requiredQuorum_) return minTimestamp_;
        }

        revert NotEnoughValidSignatures();
    }

    function _isValidSignature(
        uint256 amount_,
        string memory metadata_,
        uint256[] memory retrieveIds_,
        address validator_,
        uint256 timestamp_,
        bytes memory signature_,
        uint256 updateInterval_,
        uint256 lastUpdated_
    ) internal view returns (bool) {
        // Check that validator is approved by SPOG
        if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_)) return false;

        // Timestamp time range sanity checks
        if (block.timestamp > timestamp_ + updateInterval_) return false; // expired timestamp
        if (lastUpdated_ > timestamp_) return false; // stale timestamp

        // Check that ECDSA or ERC1271 signatures for given digest are valid
        bytes32 digest_ = _getUpdateCollateralDigest(msg.sender, amount_, metadata_, timestamp_, retrieveIds_);
        return SignatureChecker.isValidSignature(validator_, digest_, signature_);
    }

    function _allowedOutstandingValueOf(address minter_) internal view returns (uint256) {
        CollateralBasic storage minterCollateral_ = collateralOf[minter_];

        // if collateral was not updated on time, assume that minter_ CV is zero
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        if (minterCollateral_.lastUpdated + updateInterval_ < block.timestamp) return 0;

        uint256 mintRatio_ = SPOGRegistrarReader.getMintRatio(spogRegistrar);
        return (minterCollateral_.amount * mintRatio_) / ONE;
    }

    function _outstandingValueOf(address minter_) internal view returns (uint256) {
        uint256 principalValue_ = normalizedPrincipalOf[minter_];
        return _getOutstandingValue(principalValue_);
    }

    function _getOutstandingValue(uint256 principalValue_) internal view returns (uint256) {
        return _getPresentAmount(principalValue_, currentIndex());
    }

    function _getPrincipalValue(uint256 amount_) internal view returns (uint256) {
        return _getPrincipalAmount(amount_, currentIndex());
    }

    function _getPenalty(uint256 penaltyBase_) internal view returns (uint256) {
        return (penaltyBase_ * SPOGRegistrarReader.getPenalty(spogRegistrar)) / ONE;
    }

    function _getUnaccruedPenaltyForExpiredCollateralValue(address minter_) internal view returns (uint256) {
        (uint256 penaltyBase_, ) = _getPenaltyBaseAndTimeForExpiredCollateralValue(minter_);
        return _getPenalty(penaltyBase_);
    }

    function _getPenaltyBaseAndTimeForExpiredCollateralValue(
        address minter_
    ) internal view returns (uint256 penaltyBase_, uint256 penalizedUntil_) {
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        CollateralBasic storage minterCollateral_ = collateralOf[minter_];

        uint256 penalizeFrom_ = _max(minterCollateral_.lastUpdated, minterCollateral_.penalizedUntil);
        uint256 missedIntervals_ = (block.timestamp - penalizeFrom_) / updateInterval_;

        penaltyBase_ = missedIntervals_ * _outstandingValueOf(minter_);
        penalizedUntil_ = penalizeFrom_ + (missedIntervals_ * updateInterval_);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ < b_ ? a_ : b_;
    }

    function _max(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? a_ : b_;
    }

    function _rate() internal view override returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getMinterRateModel(spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IInterestRateModel.rate.selector)
        );

        return success_ ? abi.decode(returnData_, (uint256)) : 0;
    }

    function _revertIfNotApprovedMinter(address minter_) internal view {
        if (!SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_)) revert NotApprovedMinter();
    }

    function _revertIfNotApprovedValidator(address validator_) internal view {
        if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_)) revert NotApprovedValidator();
    }
}
