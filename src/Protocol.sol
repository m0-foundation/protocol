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

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    // keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)")
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        0x3b34d4b7e06822de00fa7c183f0ae7b84849881fa0e2bbf2790f8bf7702492a4;

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
        uint256 timestamp_,
        string memory metadata_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length) revert InvalidSignaturesLength();

        // Timestamp sanity checks
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        if (block.timestamp >= timestamp_ + updateInterval_) revert ExpiredTimestamp();

        address minter_ = msg.sender;

        CollateralBasic storage minterCollateral_ = collateralOf[minter_];
        if (minterCollateral_.lastUpdated > timestamp_) revert StaleTimestamp();

        // Validate that quorum of signatures was collected
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = SPOGRegistrarReader.getUpdateCollateralQuorum(spogRegistrar);
        _revertIfInsufficientValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // If minter_ is penalized, total normalized M principal is changing
        updateIndex();

        _accruePenaltyForExpiredCollateralValue(minter_);

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        _accruePenaltyForExcessiveOutstandingValue(minter_);

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
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

    // TODO: proposeRedeem
    // TODO: redeem

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

        // Note: instead of accruing, calculate value and add it to removedOutstandingValueOf to save gas
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

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method
     * @param minter_ The address of the minter
     * @param amount_ The amount of collateral
     * @param metadata_ The metadata of the collateral update, reserved for future informational use
     * @param timestamp_ The timestamp of the collateral update
     */
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 amount_,
        string memory metadata_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return _getDigest(keccak256(abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, amount_, metadata_, timestamp_)));
    }

    function _getExcessMintedValue() internal view returns (uint256 excessMintedValue_) {
        uint256 totalSupply_ = IMToken(mToken).totalSupply();
        uint256 totalOutstandingValue_ = _getOutstandingValue(totalNormalizedPrincipal);

        if (totalOutstandingValue_ > totalSupply_) return totalOutstandingValue_ - totalSupply_;
    }

    /**
     * @notice Checks that enough valid unique signatures were provided
     * @param digest_ The message hash for signing
     * @param validators_ The list of validators who signed digest
     * @param signatures_ The list of digest signatures
     * @param requiredQuorum_ The number of signatures required for action to be considered valid
     */
    function _revertIfInsufficientValidSignatures(
        bytes32 digest_,
        address[] calldata validators_,
        bytes[] calldata signatures_,
        uint256 requiredQuorum_
    ) internal view {
        if (validators_.length < requiredQuorum_) revert NotEnoughValidSignatures();

        uint256 validSignaturesNum_ = 0;

        for (uint256 index_ = 0; index_ < signatures_.length; index_++) {
            address validator_ = validators_[index_];

            // Check that validator address is unique and not accounted for
            bool duplicate_ = index_ > 0 && validator_ <= validators_[index_ - 1];
            if (duplicate_) continue;

            // Check that validator is approved by SPOG
            bool authorized_ = SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_);
            if (!authorized_) continue;

            // Check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid_ = SignatureChecker.isValidSignature(validator_, digest_, signatures_[index_]);
            if (!valid_) continue;

            // Stop processing if quorum was reached
            if (++validSignaturesNum_ == requiredQuorum_) return;
        }

        revert NotEnoughValidSignatures();
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
