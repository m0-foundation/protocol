// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IContinuousIndexing } from "./interfaces/IContinuousIndexing.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";

import { ContinuousIndexing } from "./ContinuousIndexing.sol";
import { StatelessERC712 } from "./StatelessERC712.sol";

/**
 * @title Protocol
 * @author M^ZERO LABS_
 * @notice Core protocol of M^ZERO ecosystem. TODO Add description.
 */
contract Protocol is IProtocol, ContinuousIndexing, StatelessERC712 {
    // TODO: bit-packing
    struct MinterCollateral {
        uint256 amount;
        uint256 lastUpdated;
        uint256 penalizedUntil; // for missed update collateral intervals only
    }

    // TODO: bit-packing
    struct MintProposal {
        uint256 id; // TODO: uint96 or uint48 if 2 additional fields
        address destination;
        uint256 amount;
        uint256 createdAt;
    }

    struct CollateralUpdateInfo {
        uint256 amount;
        bytes metadata;
        uint256[] retrieveIds;
        address[] validators;
        uint256[] timestamps;
        bytes[] signatures;
    }

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    // keccak256("UpdateCollateral(address minter,uint256 collateral,bytes32 metadata,uint256[] retrievalIds,uint256 timestamp)")
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        0x075a2932588882647f4c518ee54713ffd8cfe51ff373b41bee129d5be4570d45;

    uint256 public constant ONE = 10_000; // 100% in basis points.

    address public immutable spogRegistrar;
    address public immutable spogVault;
    address public immutable mToken;

    uint256 public totalPrincipalOfActiveOwedM;

    uint256 public totalInactiveOwedM;

    mapping(address minter => MinterCollateral basic) public collateralOf;

    mapping(address minter => MintProposal proposal) public mintProposalOf;

    mapping(address minter => uint256 timestamp) public unfrozenTimeOf;

    mapping(address minter => uint256 amount) public principalOfActiveOwedMOf;

    mapping(address minter => uint256 amount) public inactiveOwedMOf;

    mapping(address minter => uint256 amount) public totalCollateralPendingRetrievalOf;

    mapping(address minter => mapping(uint256 retrievalId => uint256 amount)) public pendingRetrievalsOf;

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
    constructor(address spogRegistrar_, address mToken_) ContinuousIndexing() StatelessERC712("Protocol") {
        if ((spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
        if ((spogVault = SPOGRegistrarReader.getVault(spogRegistrar_)) == address(0)) revert ZeroSpogVault();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    function updateCollateral(
        uint256 collateral_,
        bytes32 metadata_,
        uint256[] calldata retrievalIds_,
        address[] calldata validators_,
        uint256[] calldata timestamps_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length || signatures_.length != timestamps_.length) {
            revert SignatureArrayLengthsMismatch();
        }

        // Validate that enough valid signatures are provided.
        uint256 minTimestamp_ = _verifyValidatorSignatures(
            msg.sender,
            collateral_,
            metadata_,
            retrievalIds_,
            timestamps_,
            validators_,
            signatures_
        );
        // If threshold is 0, no signatures are required and current timestamp is used
        uint256 updateTimestamp_ = minTimestamp_ == 0 ? block.timestamp : minTimestamp_;

        // If minter_ is penalized, total active owed M is changing
        updateIndex();

        // Resolve given pending retrievals
        _resolvePendingRetrievals(msg.sender, retrievalIds_);

        // Impose penalty for any missed collateral updates
        _imposePenaltyIfMissedCollateralUpdates(msg.sender);

        // Update collateral
        _updateCollateral(msg.sender, collateral_, updateTimestamp_, metadata_);

        // Impose penalty if there is excessive owed M
        _imposePenaltyIfUndercollateralized(msg.sender);
    }

    function proposeMint(uint256 amount_, address destination_) external onlyApprovedMinter returns (uint256) {
        address minter_ = msg.sender;
        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < unfrozenTimeOf[msg.sender]) revert FrozenMinter();

        // Check that minter will remain sufficiently collateralized
        _revertIfUndercollateralized(minter_, amount_);

        uint256 mintId_ = uint256(keccak256(abi.encode(minter_, amount_, destination_, now_, gasleft())));

        // Save mint request info
        MintProposal storage mintProposal_ = mintProposalOf[minter_];
        mintProposal_.id = mintId_;
        mintProposal_.destination = destination_;
        mintProposal_.amount = amount_;
        mintProposal_.createdAt = now_;

        emit MintProposed(mintId_, minter_, amount_, destination_);

        return mintId_;
    }

    function mintM(uint256 mintId_) external onlyApprovedMinter {
        address minter_ = msg.sender;

        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < unfrozenTimeOf[minter_]) revert FrozenMinter();

        MintProposal storage mintProposal_ = mintProposalOf[minter_];

        // Inconsistent mintId_
        if (mintProposal_.id != mintId_) revert InvalidMintProposal();

        // Check that mint proposal is executable
        (uint256 amount_, uint256 createdAt_, address destination_) = (
            mintProposal_.amount,
            mintProposal_.createdAt,
            mintProposal_.destination
        );

        uint256 activeAt_ = createdAt_ + SPOGRegistrarReader.getMintDelay(spogRegistrar);
        if (now_ < activeAt_) revert PendingMintProposal();

        uint256 expiresAt_ = activeAt_ + SPOGRegistrarReader.getMintTTL(spogRegistrar);
        if (now_ > expiresAt_) revert ExpiredMintProposal();

        // Check that minter will remain sufficiently collateralized
        _revertIfUndercollateralized(minter_, amount_);

        updateIndex();

        // Delete mint request
        delete mintProposalOf[minter_];

        // Adjust principal of active owed M for minter
        uint256 principalAmount_ = _getPrincipalValue(amount_);
        principalOfActiveOwedMOf[minter_] += principalAmount_;
        totalPrincipalOfActiveOwedM += principalAmount_;

        // Mint actual M tokens
        IMToken(mToken).mint(destination_, amount_);

        emit MintExecuted(mintId_, minter_, amount_, destination_);
    }

    function cancelMint(uint256 mintId_) external onlyApprovedMinter {
        _cancelMint(msg.sender, mintId_);
    }

    function proposeRetrieval(uint256 amount_) external onlyApprovedMinter returns (uint256) {
        address minter_ = msg.sender;

        uint256 outstandingValueSurplus_ = (amount_ * SPOGRegistrarReader.getMintRatio(spogRegistrar)) / ONE;
        // TODO: consider if we need it for small amounts because of rounding
        // if (retrieveOutstandingValue_ == 0) revert RetrieveAmountTooSmall();

        _revertIfUndercollateralized(minter_, outstandingValueSurplus_); // TODO: Fix `outstandingValueSurplus_` name.

        uint256 retrievalId_ = uint256(keccak256(abi.encode(minter_, amount_, block.timestamp, gasleft())));

        totalCollateralPendingRetrievalOf[minter_] += amount_;
        pendingRetrievalsOf[minter_][retrievalId_] = amount_;

        emit RetrievalCreated(retrievalId_, minter_, amount_);

        return retrievalId_;
    }

    function burnM(address minter_, uint256 amount_) external {
        updateIndex();

        _imposePenaltyIfMissedCollateralUpdates(minter_);

        uint256 repayAmount_ = SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_) // TODO: Unclear.
            ? _repayForActiveMinter(minter_, amount_)
            : _repayForInactiveMinter(minter_, amount_);

        // Burn actual M tokens
        IMToken(mToken).burn(msg.sender, repayAmount_);

        emit BurnExecuted(minter_, repayAmount_, msg.sender);
    }

    function deactivateMinter(address minter_) external {
        if (SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_)) revert StillApprovedMinter();

        updateIndex();

        // TODO: Instead of imposing, calculate penalty and add it to `inactiveOwedMOf` to save gas
        uint256 penalty_ = _getPenaltyForMissedCollateralUpdates(minter_); // TODO: And for undercollateralization?
        uint256 inactiveOwedM_ = _getActiveOwedM(minter_) + penalty_;

        // TODO: Do not allow setting inactiveOwedMOf to 0 by calling this function multiple times
        inactiveOwedMOf[minter_] += inactiveOwedM_;
        totalInactiveOwedM += inactiveOwedM_;

        // Adjust total principal of owen M by imposing interest principal
        totalPrincipalOfActiveOwedM -= principalOfActiveOwedMOf[minter_];

        // Reset minter's state
        delete principalOfActiveOwedMOf[minter_];
        delete collateralOf[minter_];
        delete mintProposalOf[minter_];
        delete unfrozenTimeOf[minter_];
        delete totalCollateralPendingRetrievalOf[minter_]; // TODO: cannot delete retrievals. This is not ideal.

        emit MinterDeactivated(minter_, inactiveOwedM_, msg.sender);
    }

    function activeOwedMOf(address minter_) external view returns (uint256) {
        return _getActiveOwedM(minter_);
    }

    function getPenaltyForMissedCollateralUpdates(address minter_) external view returns (uint256) {
        return _getPenaltyForMissedCollateralUpdates(minter_);
    }

    /******************************************************************************************************************\
    |                                                Validator Functions                                               |
    \******************************************************************************************************************/

    function cancelMint(address minter_, uint256 mintId_) external onlyApprovedValidator {
        _cancelMint(minter_, mintId_);
    }

    function freezeMinter(address minter_) external onlyApprovedValidator {
        uint256 frozenUntil_ = block.timestamp + SPOGRegistrarReader.getMinterFreezeTime(spogRegistrar);

        emit MinterFrozen(minter_, unfrozenTimeOf[minter_] = frozenUntil_);
    }

    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/

    function updateIndex() public override(IContinuousIndexing, ContinuousIndexing) returns (uint256 index_) {
        // TODO: Order of these matter if their rate models depend on the same utilization ratio / total supplies.
        index_ = super.updateIndex(); // Update Minter index.

        IMToken(mToken).updateIndex(); // Update Earning index.

        // Mint M to Zero Vault
        uint256 excessOwedM_ = _getExcessOwedM();

        if (excessOwedM_ > 0) IMToken(mToken).mint(spogVault, excessOwedM_);
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _imposePenalty(address minter_, uint256 penaltyBase_) internal {
        uint256 penalty_ = _getPenalty(penaltyBase_);

        uint256 penaltyPrincipal_ = _getPrincipalValue(penalty_);
        principalOfActiveOwedMOf[minter_] += penaltyPrincipal_;
        totalPrincipalOfActiveOwedM += penaltyPrincipal_;

        emit PenaltyImposed(minter_, penalty_, msg.sender);
    }

    function _imposePenaltyIfMissedCollateralUpdates(address minter_) internal {
        (uint256 penaltyBase_, uint256 penalizedUntil_) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);

        // Save penalization interval to not double charge for missed periods again
        collateralOf[minter_].penalizedUntil = penalizedUntil_;

        _imposePenalty(minter_, penaltyBase_);
    }

    function _imposePenaltyIfUndercollateralized(address minter_) internal {
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = _getActiveOwedM(minter_);

        if (maxOwedM_ >= activeOwedM_) return;

        _imposePenalty(minter_, activeOwedM_ - maxOwedM_);
    }

    function _cancelMint(address minter_, uint256 mintId_) internal {
        if (mintProposalOf[minter_].id != mintId_) revert InvalidMintProposal();

        delete mintProposalOf[minter_];

        emit MintCanceled(mintId_, minter_, msg.sender);
    }

    function _resolvePendingRetrievals(address minter_, uint256[] calldata retrievalIds_) internal {
        for (uint256 index_ = 0; index_ < retrievalIds_.length; index_++) {
            uint256 retrievalId_ = retrievalIds_[index_];
            uint256 collateral_ = pendingRetrievalsOf[minter_][retrievalId_];

            delete pendingRetrievalsOf[minter_][retrievalId_];
            totalCollateralPendingRetrievalOf[minter_] -= collateral_;

            emit RetrievalClosed(retrievalId_, minter_, collateral_);
        }
    }

    function _updateCollateral(address minter_, uint256 amount_, uint256 newTimestamp_, bytes32 metadata_) internal {
        MinterCollateral storage minterCollateral_ = collateralOf[minter_];

        uint256 lastUpdated_ = minterCollateral_.lastUpdated;

        // TODO: If the `lastUpdated_` is 0 (for fresh minters), any timestamp, even really old ones, will be
        //       valid. Only harm is if the minter's first collateral update ever has a "bad" timestamp chosen by a
        //       validator.
        if (newTimestamp_ < lastUpdated_) revert StaleCollateralUpdate();

        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = newTimestamp_;

        emit CollateralUpdated(minter_, amount_, metadata_, newTimestamp_);
    }

    /**
     * @notice Checks that enough valid unique signatures were provided
     * @param minter_ The address of the minter
     * @param collateral_ The amount of collateral
     * @param metadata_ The hash of metadata of the collateral update, reserved for future informational use
     * @param retrievalIds_ The list of proposed collateral retrieval IDs to resolve
     * @param validators_ The list of validators
     * @param timestamps_ The list of validator timestamps for the collateral update signatures
     * @param signatures_ The list of signatures
     * @return minTimestamp_ The minimum timestamp across all valid timestamps with valid signatures
     */
    function _verifyValidatorSignatures(
        address minter_,
        uint256 collateral_,
        bytes32 metadata_,
        uint256[] calldata retrievalIds_,
        uint256[] calldata timestamps_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) internal view returns (uint256 minTimestamp_) {
        uint256 threshold_ = SPOGRegistrarReader.getUpdateCollateralValidatorThreshold(spogRegistrar);

        // Stop processing if there ar eno more signatures or `threshold_` is reached.
        for (uint256 index_; index_ < signatures_.length && threshold_ > 0; ++index_) {
            // Check that validator address is unique and not accounted for
            // NOTE: We revert here because this failure is entirely within the minter's control.
            if (index_ > 0 && validators_[index_] <= validators_[index_ - 1]) revert InvalidSignatureOrder();

            // Check that the timestamp is not in the future.
            if (timestamps_[index_] > block.timestamp) revert FutureTimestamp();

            bytes32 digest_ = _getUpdateCollateralDigest(
                minter_,
                collateral_,
                metadata_,
                retrievalIds_,
                timestamps_[index_]
            );

            // Check that validator is approved by SPOG.
            if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validators_[index_])) continue;

            // Check that ECDSA or ERC1271 signatures for given digest are valid.
            if (!SignatureChecker.isValidSignature(validators_[index_], digest_, signatures_[index_])) continue;

            // Find minimum between all valid timestamps for valid signatures
            minTimestamp_ = _minIgnoreZero(minTimestamp_, timestamps_[index_]);

            --threshold_;
        }

        if (threshold_ > 0) revert NotEnoughValidSignatures();
    }

    function _repayForActiveMinter(address minter_, uint256 amount_) internal returns (uint256) {
        uint256 repayAmount_ = _min(_getActiveOwedM(minter_), amount_);
        uint256 repayPrincipal_ = _getPrincipalValue(repayAmount_);

        principalOfActiveOwedMOf[minter_] -= repayPrincipal_;
        totalPrincipalOfActiveOwedM -= repayPrincipal_;

        return repayAmount_;
    }

    function _repayForInactiveMinter(address minter_, uint256 amount_) internal returns (uint256) {
        uint256 repayAmount_ = _min(inactiveOwedMOf[minter_], amount_);

        inactiveOwedMOf[minter_] -= repayAmount_;
        totalInactiveOwedM -= repayAmount_;

        return repayAmount_;
    }

    function _revertIfUndercollateralized(address minter_, uint256 additionalOwedM_) internal view {
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = _getActiveOwedM(minter_);

        if (activeOwedM_ + additionalOwedM_ > maxOwedM_) revert Undercollateralized();
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method
     * @param minter_ The address of the minter
     * @param collateral_ The amount of collateral
     * @param metadata_ The metadata of the collateral update, reserved for future informational use
     * @param retrievalIds_ The list of proposed collateral retrieval IDs to resolve
     * @param timestamp_ The timestamp of the collateral update
     */
    function _getUpdateCollateralDigest(
        address minter_,
        uint256 collateral_,
        bytes32 metadata_,
        uint256[] calldata retrievalIds_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return
            _getDigest(
                keccak256(
                    abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, collateral_, metadata_, retrievalIds_, timestamp_)
                )
            );
    }

    function _getExcessOwedM() internal view returns (uint256 getExcessOwedM_) {
        uint256 totalMSupply_ = IMToken(mToken).totalSupply();
        uint256 totalActiveOwedM_ = _getPresentValue(totalPrincipalOfActiveOwedM);

        if (totalActiveOwedM_ > totalMSupply_) return totalActiveOwedM_ - totalMSupply_;
    }

    function _getMaxOwedM(address minter_) internal view returns (uint256) {
        MinterCollateral storage minterCollateral_ = collateralOf[minter_];
        uint256 collateralNetOfPendingRetrievals_ = minterCollateral_.amount -
            totalCollateralPendingRetrievalOf[minter_];

        // If collateral was not updated on time, assume that minter_'s collateral is zero
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        if (minterCollateral_.lastUpdated + updateInterval_ < block.timestamp) return 0;

        uint256 mintRatio_ = SPOGRegistrarReader.getMintRatio(spogRegistrar);
        return (collateralNetOfPendingRetrievals_ * mintRatio_) / ONE;
    }

    function _getActiveOwedM(address minter_) internal view returns (uint256) {
        uint256 principalOfActiveOwedM_ = principalOfActiveOwedMOf[minter_];
        return _getPresentValue(principalOfActiveOwedM_);
    }

    function _getPresentValue(uint256 principalValue_) internal view returns (uint256) {
        return _getPresentAmount(principalValue_, currentIndex());
    }

    function _getPrincipalValue(uint256 presentValue_) internal view returns (uint256) {
        return _getPrincipalAmount(presentValue_, currentIndex());
    }

    function _getPenalty(uint256 penaltyBase_) internal view returns (uint256) {
        return (penaltyBase_ * SPOGRegistrarReader.getPenalty(spogRegistrar)) / ONE;
    }

    function _getPenaltyForMissedCollateralUpdates(address minter_) internal view returns (uint256) {
        (uint256 penaltyBase_, ) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);
        return _getPenalty(penaltyBase_);
    }

    function _getPenaltyBaseAndTimeForMissedCollateralUpdates(
        address minter_
    ) internal view returns (uint256 penaltyBase_, uint256 penalizedUntil_) {
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        MinterCollateral storage minterCollateral_ = collateralOf[minter_];

        uint256 penalizeFrom_ = _max(minterCollateral_.lastUpdated, minterCollateral_.penalizedUntil);
        uint256 missedIntervals_ = (block.timestamp - penalizeFrom_) / updateInterval_;

        penaltyBase_ = missedIntervals_ * _getActiveOwedM(minter_);
        penalizedUntil_ = penalizeFrom_ + (missedIntervals_ * updateInterval_);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ < b_ ? a_ : b_;
    }

    function _minIgnoreZero(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ == 0 ? b_ : _min(a_, b_);
    }

    function _max(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? a_ : b_;
    }

    function _rate() internal view override returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getMinterRateModel(spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IRateModel.rate.selector)
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
