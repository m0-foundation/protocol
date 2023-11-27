// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IContinuousIndexing } from "./interfaces/IContinuousIndexing.sol";
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
    struct MintProposal {
        uint256 id; // TODO: uint96 or uint48 if 2 additional fields
        address destination;
        uint256 amount;
        uint256 createdAt;
    }

    /******************************************************************************************************************\
    |                                                    Variables                                                     |
    \******************************************************************************************************************/

    uint256 public constant ONE = 10_000; // 100% in basis points.

    // keccak256("UpdateCollateral(address minter,uint256 collateral,uint256[] retrievalIds,bytes32 metadata,uint256 timestamp)")
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        0x03e759b5837dd0858df38108bd60b1bc91d4d860c1947922e31e9fdb35f0882f;

    address public immutable spogRegistrar;
    address public immutable spogVault;
    address public immutable mToken;

    /// @notice Nonce used to generate unique mint and retrieval proposal IDs.
    uint256 internal _nonce;

    uint256 internal _totalPrincipalOfActiveOwedM;
    uint256 internal _totalInactiveOwedM;

    mapping(address minter => uint256 collateral) internal _collaterals;
    mapping(address minter => uint256 owedM) internal _inactiveOwedM;
    mapping(address minter => uint256 activeOwedM) internal _principalOfActiveOwedM;
    mapping(address minter => uint256 totalCollateralPendingRetrieval) internal _totalCollateralPendingRetrieval;

    mapping(address minter => uint256 updateInterval) internal _lastUpdateIntervals;
    mapping(address minter => uint256 lastUpdate) internal _lastCollateralUpdates;
    mapping(address minter => uint256 penalizedUntil) internal _penalizedUntilTimestamps;
    mapping(address minter => uint256 unfrozenTime) internal _unfrozenTimestamps;

    mapping(address minter => MintProposal proposal) internal _mintProposals;

    mapping(address minter => mapping(uint256 retrievalId => uint256 amount)) internal _pendingRetrievals;

    /******************************************************************************************************************\
    |                                            Modifiers and Constructor                                             |
    \******************************************************************************************************************/

    modifier onlyApprovedMinter() {
        _revertIfNotApprovedMinter(msg.sender);

        _;
    }

    modifier onlyApprovedValidator() {
        _revertIfNotApprovedValidator(msg.sender);

        _;
    }

    modifier onlyUnfrozenMinter() {
        _revertIfMinterFrozen(msg.sender);

        _;
    }

    /**
     * @notice Constructor.
     * @param spogRegistrar_ The address of the SPOG Registrar contract.
     * @param mToken_ The address of the M Token.
     */
    constructor(address spogRegistrar_, address mToken_) ContinuousIndexing() StatelessERC712("Protocol") {
        if ((spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
        if ((spogVault = SPOGRegistrarReader.getVault(spogRegistrar_)) == address(0)) revert ZeroSpogVault();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
    }

    /******************************************************************************************************************\
    |                                          External Interactive Functions                                          |
    \******************************************************************************************************************/

    function burnM(address minter_, uint256 maxAmount_) external {
        // NOTE: Penalize only for missed collateral updates, not for undercollateralization.
        // Undercollateralization within one update interval is forgiven.
        _imposePenaltyIfMissedCollateralUpdates(minter_);

        uint256 amount_ = _isApprovedMinter(minter_) // TODO: `isActiveMinter`.
            ? _repayForActiveMinter(minter_, maxAmount_)
            : _repayForInactiveMinter(minter_, maxAmount_);

        emit BurnExecuted(minter_, amount_, msg.sender);

        IMToken(mToken).burn(msg.sender, amount_); // Burn actual M tokens

        // NOTE: Above functionality already has access to `currentIndex()`, and since the completion of the burn
        //       can result in a new rate, we should update the index here to lock in that rate.
        updateIndex();
    }

    function cancelMint(uint256 mintId_) external onlyApprovedMinter {
        _cancelMint(msg.sender, mintId_);
    }

    function cancelMint(address minter_, uint256 mintId_) external onlyApprovedValidator {
        _cancelMint(minter_, mintId_);
    }

    function deactivateMinter(address minter_) external returns (uint256 inactiveOwedM_) {
        if (_isApprovedMinter(minter_)) revert StillApprovedMinter();

        // NOTE: Instead of imposing, calculate penalty and add it to `_inactiveOwedM` to save gas.
        // TODO: And for undercollateralization?
        inactiveOwedM_ = activeOwedMOf(minter_) + getPenaltyForMissedCollateralUpdates(minter_);

        emit MinterDeactivated(minter_, inactiveOwedM_);

        // TODO: Do not allow setting `_inactiveOwedM` to 0 by calling this function multiple times.
        _inactiveOwedM[minter_] += inactiveOwedM_;
        _totalInactiveOwedM += inactiveOwedM_;

        // Adjust total principal of owed M.
        _totalPrincipalOfActiveOwedM -= _principalOfActiveOwedM[minter_];

        // Reset reasonable aspects of minter's state.
        delete _collaterals[minter_];
        delete _lastUpdateIntervals[minter_];
        delete _lastCollateralUpdates[minter_];
        delete _mintProposals[minter_];
        delete _penalizedUntilTimestamps[minter_];
        delete _principalOfActiveOwedM[minter_];
        delete _unfrozenTimestamps[minter_];

        // NOTE: Above functionality already has access to `currentIndex()`, and since the completion of the
        //       deactivation can result in a new rate, we should update the index here to lock in that rate.
        updateIndex();
    }

    function freezeMinter(address minter_) external onlyApprovedValidator returns (uint256 frozenUntil_) {
        frozenUntil_ = block.timestamp + SPOGRegistrarReader.getMinterFreezeTime(spogRegistrar);

        emit MinterFrozen(minter_, _unfrozenTimestamps[minter_] = frozenUntil_);
    }

    function mintM(uint256 mintId_) external onlyApprovedMinter onlyUnfrozenMinter {
        MintProposal storage mintProposal_ = _mintProposals[msg.sender];

        (uint256 id_, uint256 amount_, uint256 createdAt_, address destination_) = (
            mintProposal_.id,
            mintProposal_.amount,
            mintProposal_.createdAt,
            mintProposal_.destination
        );

        if (id_ != mintId_) revert InvalidMintProposal();

        // Check that mint proposal is executable.
        uint256 activeAt_ = createdAt_ + SPOGRegistrarReader.getMintDelay(spogRegistrar);
        if (block.timestamp < activeAt_) revert PendingMintProposal();

        uint256 expiresAt_ = activeAt_ + SPOGRegistrarReader.getMintTTL(spogRegistrar);
        if (block.timestamp > expiresAt_) revert ExpiredMintProposal();

        _revertIfUndercollateralized(msg.sender, amount_); // Check that minter will remain sufficiently collateralized.

        delete _mintProposals[msg.sender]; // Delete mint request.

        emit MintExecuted(mintId_);

        // Adjust principal of active owed M for minter.
        uint256 principalAmount_ = _getPrincipalValue(amount_);
        _principalOfActiveOwedM[msg.sender] += principalAmount_;
        _totalPrincipalOfActiveOwedM += principalAmount_;

        IMToken(mToken).mint(destination_, amount_);

        // NOTE: Above functionality already has access to `currentIndex()`, and since the completion of the mint
        //       can result in a new rate, we should update the index here to lock in that rate.
        updateIndex();
    }

    function proposeMint(
        uint256 amount_,
        address destination_
    ) external onlyApprovedMinter onlyUnfrozenMinter returns (uint256 mintId_) {
        _revertIfUndercollateralized(msg.sender, amount_); // Check that minter will remain sufficiently collateralized.

        uint256 nonce_ = _incrementNonce();
        mintId_ = uint256(keccak256(abi.encode(msg.sender, amount_, destination_, nonce_)));

        _mintProposals[msg.sender] = MintProposal(mintId_, destination_, amount_, block.timestamp);

        emit MintProposed(mintId_, msg.sender, amount_, destination_);
    }

    function proposeRetrieval(uint256 collateral_) external onlyApprovedMinter returns (uint256 retrievalId_) {
        uint256 nonce_ = _incrementNonce();
        retrievalId_ = uint256(keccak256(abi.encode(msg.sender, collateral_, nonce_)));

        _totalCollateralPendingRetrieval[msg.sender] += collateral_;
        _pendingRetrievals[msg.sender][retrievalId_] = collateral_;

        _revertIfUndercollateralized(msg.sender, 0);

        emit RetrievalCreated(retrievalId_, msg.sender, collateral_);
    }

    function updateCollateral(
        uint256 collateral_,
        uint256[] calldata retrievalIds_,
        bytes32 metadata_,
        address[] calldata validators_,
        uint256[] calldata timestamps_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter returns (uint256 minTimestamp_) {
        if (validators_.length != signatures_.length || signatures_.length != timestamps_.length) {
            revert SignatureArrayLengthsMismatch();
        }

        // Verify that enough valid signatures are provided, and get the minimum timestamp across all valid signatures.
        minTimestamp_ = _verifyValidatorSignatures(
            msg.sender,
            collateral_,
            retrievalIds_,
            metadata_,
            timestamps_,
            validators_,
            signatures_
        );

        emit CollateralUpdated(msg.sender, collateral_, retrievalIds_, metadata_, minTimestamp_);

        _resolvePendingRetrievals(msg.sender, retrievalIds_);

        _imposePenaltyIfMissedCollateralUpdates(msg.sender);

        _updateCollateral(msg.sender, collateral_, minTimestamp_);

        _imposePenaltyIfUndercollateralized(msg.sender);

        // NOTE: Above functionality already has access to `currentIndex()`, and since the completion of the collateral
        //       update can result in a new rate, we should update the index here to lock in that rate.
        updateIndex();
    }

    function updateIndex() public override(IContinuousIndexing, ContinuousIndexing) returns (uint256 index_) {
        // NOTE: With the current rate models, the minter rate does not depend on anything in the protocol or mToken, so
        //       we can update the minter rate and index here.
        index_ = super.updateIndex(); // Update minter index and rate.

        // NOTE: Since the currentIndex of the protocol and mToken are constant thought this context's execution (since
        //       the block.timestamp is not changing) we can compute excessOwedM without updating the mToken index.
        uint256 excessOwedM_ = _getExcessOwedM();

        if (excessOwedM_ > 0) IMToken(mToken).mint(spogVault, excessOwedM_); // Mint M to SPOG Vault.

        // NOTE: Given the current implementation of the mToken transfers and its rate model, while it is possible for
        //       the above mint to already have updated the mToken index if M was minted to an earning account, we want
        //       to ensure the rate provided by the mToken's rate model is locked in.
        IMToken(mToken).updateIndex(); // Update earning index and rate.
    }

    /******************************************************************************************************************\
    |                                           External View/Pure Functions                                           |
    \******************************************************************************************************************/

    function activeOwedMOf(address minter_) public view returns (uint256 activeOwedM_) {
        // TODO: This should also include the present value of unavoidable penalities. But then it would be very, if not
        //       impossible, to determine the `totalActiveOwedM` to them same standards. Perhaps we need a `penaltiesOf`
        //       external function to provide the present value of unavoidable penalities
        return _getPresentValue(_principalOfActiveOwedM[minter_]);
    }

    function collateralOf(address minter_) public view returns (uint256 collateral_) {
        // If collateral was not updated before deadline, assume that minter's collateral is zero.
        return
            block.timestamp < collateralUpdateDeadlineOf(minter_)
                ? _collaterals[minter_] - _totalCollateralPendingRetrieval[minter_]
                : 0;
    }

    function collateralUpdateDeadlineOf(address minter_) public view returns (uint256 updateDeadline_) {
        return _lastCollateralUpdates[minter_] + _lastUpdateIntervals[minter_];
    }

    function getPenaltyForMissedCollateralUpdates(address minter_) public view returns (uint256 penalty_) {
        (uint256 penaltyBase_, ) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);

        return (penaltyBase_ * penaltyRate()) / ONE;
    }

    function inactiveOwedMOf(address minter_) external view returns (uint256 inactiveOwedM_) {
        return _inactiveOwedM[minter_];
    }

    function latestMinterRate() external view returns (uint256 latestMinterRate_) {
        return _latestRate;
    }

    function lastUpdateIntervalOf(address minter_) external view returns (uint256 lastUpdateInterval_) {
        return _lastUpdateIntervals[minter_];
    }

    function lastUpdateOf(address minter_) external view returns (uint256 lastUpdate_) {
        return _lastCollateralUpdates[minter_];
    }

    function minterRate() external view returns (uint256 minterRate_) {
        return _rate();
    }

    function mintProposalOf(
        address minter_
    ) external view returns (uint256 mintId_, address destination_, uint256 amount_, uint256 createdAt_) {
        mintId_ = _mintProposals[minter_].id;
        destination_ = _mintProposals[minter_].destination;
        amount_ = _mintProposals[minter_].amount;
        createdAt_ = _mintProposals[minter_].createdAt;
    }

    function mintRatio() public view returns (uint256 mintRatio_) {
        return SPOGRegistrarReader.getMintRatio(spogRegistrar);
    }

    function penalizedUntilOf(address minter_) external view returns (uint256 penalizedUntil_) {
        return _penalizedUntilTimestamps[minter_];
    }

    function penaltyRate() public view returns (uint256 penaltyRate_) {
        return SPOGRegistrarReader.getPenaltyRate(spogRegistrar);
    }

    function pendingRetrievalsOf(address minter_, uint256 retrievalId_) external view returns (uint256 collateral) {
        return _pendingRetrievals[minter_][retrievalId_];
    }

    function totalActiveOwedM() public view returns (uint256 totalActiveOwedM_) {
        return _getPresentValue(_totalPrincipalOfActiveOwedM);
    }

    function totalCollateralPendingRetrievalOf(address minter_) external view returns (uint256 collateral_) {
        return _totalCollateralPendingRetrieval[minter_];
    }

    function totalInactiveOwedM() public view returns (uint256 totalInactiveOwedM_) {
        return _totalInactiveOwedM;
    }

    function totalOwedM() external view returns (uint256 totalOwedM_) {
        return totalActiveOwedM() + totalInactiveOwedM();
    }

    function unfrozenTimeOf(address minter_) external view returns (uint256 timestamp_) {
        return _unfrozenTimestamps[minter_];
    }

    function updateCollateralInterval() public view returns (uint256 updateCollateralInterval_) {
        return SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _cancelMint(address minter_, uint256 mintId_) internal {
        if (_mintProposals[minter_].id != mintId_) revert InvalidMintProposal();

        delete _mintProposals[minter_];

        emit MintCanceled(mintId_, msg.sender);
    }

    function _imposePenalty(address minter_, uint256 penaltyBase_) internal {
        // TODO: The rate being charged for a late interval should be M per active owed M.
        // TODO: The rate being charged for a undercollateralization should be M per second per excess active owed M.
        // TODO: The above 2 are not remotely the same units, let alone the same rate. Fix.
        uint256 penalty_ = (penaltyBase_ * penaltyRate()) / ONE;
        uint256 penaltyPrincipal_ = _getPrincipalValue(penalty_);

        _principalOfActiveOwedM[minter_] += penaltyPrincipal_;
        _totalPrincipalOfActiveOwedM += penaltyPrincipal_;

        emit PenaltyImposed(minter_, penalty_);
    }

    function _imposePenaltyIfMissedCollateralUpdates(address minter_) internal {
        (uint256 penaltyBase_, uint256 penalizedUntil_) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);

        // Save penalization interval to not double charge for missed periods again
        _penalizedUntilTimestamps[minter_] = penalizedUntil_;

        _imposePenalty(minter_, penaltyBase_);
    }

    function _imposePenaltyIfUndercollateralized(address minter_) internal {
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = activeOwedMOf(minter_);

        if (maxOwedM_ >= activeOwedM_) return;

        _imposePenalty(minter_, activeOwedM_ - maxOwedM_);
    }

    /**
     * @notice Helper to increment nonce.
     * @return uint256 Incremented nonce
     */
    function _incrementNonce() internal returns (uint256) {
        unchecked {
            _nonce++;
        }

        return _nonce;
    }

    function _repayForActiveMinter(address minter_, uint256 maxAmount_) internal returns (uint256 amount_) {
        amount_ = _min(activeOwedMOf(minter_), maxAmount_);
        uint256 principalAmount_ = _getPrincipalValue(amount_);

        _principalOfActiveOwedM[minter_] -= principalAmount_;
        _totalPrincipalOfActiveOwedM -= principalAmount_;
    }

    function _repayForInactiveMinter(address minter_, uint256 maxAmount_) internal returns (uint256 amount_) {
        amount_ = _min(_inactiveOwedM[minter_], maxAmount_);

        _inactiveOwedM[minter_] -= amount_;
        _totalInactiveOwedM -= amount_;
    }

    function _resolvePendingRetrievals(address minter_, uint256[] calldata retrievalIds_) internal {
        for (uint256 index_; index_ < retrievalIds_.length; ++index_) {
            uint256 retrievalId_ = retrievalIds_[index_];

            _totalCollateralPendingRetrieval[minter_] -= _pendingRetrievals[minter_][retrievalId_];

            delete _pendingRetrievals[minter_][retrievalId_];
        }
    }

    function _updateCollateral(address minter_, uint256 amount_, uint256 newTimestamp_) internal {
        if (newTimestamp_ < _lastCollateralUpdates[minter_]) revert StaleCollateralUpdate();

        _collaterals[minter_] = amount_;
        _lastCollateralUpdates[minter_] = newTimestamp_;
        _lastUpdateIntervals[minter_] = updateCollateralInterval();
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function _getExcessOwedM() internal view returns (uint256 getExcessOwedM_) {
        uint256 totalMSupply_ = IMToken(mToken).totalSupply();
        uint256 totalActiveOwedM_ = _getPresentValue(_totalPrincipalOfActiveOwedM);

        if (totalActiveOwedM_ > totalMSupply_) return totalActiveOwedM_ - totalMSupply_;
    }

    function _getMaxOwedM(address minter_) internal view returns (uint256 maxOwedM_) {
        return (collateralOf(minter_) * mintRatio()) / ONE;
    }

    function _getPenaltyBaseAndTimeForMissedCollateralUpdates(
        address minter_
    ) internal view returns (uint256 penaltyBase_, uint256 penalizedUntil_) {
        uint256 updateInterval_ = _lastUpdateIntervals[minter_];
        uint256 lastUpdate_ = _lastCollateralUpdates[minter_];
        uint256 penalizeFrom_ = _max(lastUpdate_, _penalizedUntilTimestamps[minter_]);

        if (updateInterval_ == 0) return (0, penalizeFrom_);

        uint256 missedIntervals_ = (block.timestamp - penalizeFrom_) / updateInterval_;

        penaltyBase_ = missedIntervals_ * activeOwedMOf(minter_);
        penalizedUntil_ = penalizeFrom_ + (missedIntervals_ * updateInterval_);
    }

    function _getPresentValue(uint256 principalValue_) internal view returns (uint256 presentValue_) {
        return _getPresentAmount(principalValue_, currentIndex());
    }

    function _getPrincipalValue(uint256 presentValue_) internal view returns (uint256 principalValue_) {
        return _getPrincipalAmount(presentValue_, currentIndex());
    }

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
        uint256[] calldata retrievalIds_,
        bytes32 metadata_,
        uint256 timestamp_
    ) internal view returns (bytes32) {
        return
            _getDigest(
                keccak256(
                    abi.encode(UPDATE_COLLATERAL_TYPEHASH, minter_, collateral_, retrievalIds_, metadata_, timestamp_)
                )
            );
    }

    function _isApprovedMinter(address minter_) internal view returns (bool isApproved_) {
        return SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_);
    }

    function _max(uint256 a_, uint256 b_) internal pure returns (uint256 max_) {
        return a_ > b_ ? a_ : b_;
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ < b_ ? a_ : b_;
    }

    function _minIgnoreZero(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ == 0 ? b_ : _min(a_, b_);
    }

    function _rate() internal view override returns (uint256 rate_) {
        rate_ = SPOGRegistrarReader.getMinterRate(spogRegistrar);
    }

    function _revertIfMinterFrozen(address minter_) internal view {
        if (block.timestamp < _unfrozenTimestamps[minter_]) revert FrozenMinter();
    }

    function _revertIfNotApprovedMinter(address minter_) internal view {
        if (!_isApprovedMinter(minter_)) revert NotApprovedMinter();
    }

    function _revertIfNotApprovedValidator(address validator_) internal view {
        if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_)) revert NotApprovedValidator();
    }

    function _revertIfUndercollateralized(address minter_, uint256 additionalOwedM_) internal view {
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = activeOwedMOf(minter_);

        if (activeOwedM_ + additionalOwedM_ > maxOwedM_) revert Undercollateralized();
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
        uint256[] calldata retrievalIds_,
        bytes32 metadata_,
        uint256[] calldata timestamps_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) internal view returns (uint256 minTimestamp_) {
        uint256 threshold_ = SPOGRegistrarReader.getUpdateCollateralValidatorThreshold(spogRegistrar);

        minTimestamp_ = block.timestamp;

        // Stop processing if there are no more signatures or `threshold_` is reached.
        for (uint256 index_; index_ < signatures_.length && threshold_ > 0; ++index_) {
            // Check that validator address is unique and not accounted for
            // NOTE: We revert here because this failure is entirely within the minter's control.
            if (index_ > 0 && validators_[index_] <= validators_[index_ - 1]) revert InvalidSignatureOrder();

            // Check that the timestamp is not in the future.
            if (timestamps_[index_] > block.timestamp) revert FutureTimestamp();

            bytes32 digest_ = _getUpdateCollateralDigest(
                minter_,
                collateral_,
                retrievalIds_,
                metadata_,
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
}
