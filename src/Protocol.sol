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

// TODO: Penalties are awkwardly and inconsistently defined and implemented.

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

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    // keccak256("UpdateCollateral(address minter,uint256 collateral,bytes32 metadata,uint256[] retrievalIds,uint256 timestamp)")
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        0x075a2932588882647f4c518ee54713ffd8cfe51ff373b41bee129d5be4570d45;

    uint256 internal constant _ONE = 10_000; // 100% in basis points.

    address internal immutable _spogRegistrar;
    address internal immutable _spogVault;
    address internal immutable _mToken;

    uint256 internal _totalPrincipalOfActiveOwedM;
    uint256 internal _totalInactiveOwedM;

    mapping(address minter => MinterCollateral basic) internal _collaterals;

    mapping(address minter => MintProposal proposal) internal _mintProposals;

    mapping(address minter => uint256 timestamp) internal _unfrozenTimes;

    mapping(address minter => uint256 amount) internal _principalOfActiveOwedM;

    mapping(address minter => uint256 amount) internal _inactiveOwedM;

    mapping(address minter => uint256 amount) internal _totalCollateralPendingRetrieval;

    mapping(address minter => mapping(uint256 retrievalId => uint256 amount)) internal _pendingRetrievals;

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
     */
    constructor(address spogRegistrar_, address mToken_) ContinuousIndexing() StatelessERC712("Protocol") {
        if ((_spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
        if ((_spogVault = SPOGRegistrarReader.getVault(spogRegistrar_)) == address(0)) revert ZeroSpogVault();
        if ((_mToken = mToken_) == address(0)) revert ZeroMToken();
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

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

        updateIndex(); // If minter is penalized, total active owed M is changing.

        _resolvePendingRetrievals(msg.sender, retrievalIds_);

        _imposePenaltyIfMissedCollateralUpdates(msg.sender);

        _updateCollateral(msg.sender, collateral_, minTimestamp_);

        _imposePenaltyIfUndercollateralized(msg.sender);
    }

    function proposeMint(
        uint256 amount_,
        address destination_
    ) external onlyApprovedMinter onlyUnfrozenMinter returns (uint256 mintId_) {
        _revertIfUndercollateralized(msg.sender, amount_); // Check that minter will remain sufficiently collateralized.

        mintId_ = uint256(keccak256(abi.encode(msg.sender, amount_, destination_, block.timestamp)));

        _mintProposals[msg.sender] = MintProposal(mintId_, destination_, amount_, block.timestamp);

        emit MintProposed(mintId_, msg.sender, amount_, destination_);
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
        uint256 activeAt_ = createdAt_ + SPOGRegistrarReader.getMintDelay(_spogRegistrar);
        if (block.timestamp < activeAt_) revert PendingMintProposal();

        uint256 expiresAt_ = activeAt_ + SPOGRegistrarReader.getMintTTL(_spogRegistrar);
        if (block.timestamp > expiresAt_) revert ExpiredMintProposal();

        _revertIfUndercollateralized(msg.sender, amount_); // Check that minter will remain sufficiently collateralized.

        // Delete mint request
        delete _mintProposals[msg.sender];

        emit MintExecuted(mintId_);

        updateIndex();

        // Adjust principal of active owed M for minter.
        uint256 principalAmount_ = _getPrincipalValue(amount_);
        _principalOfActiveOwedM[msg.sender] += principalAmount_;
        _totalPrincipalOfActiveOwedM += principalAmount_;

        IMToken(_mToken).mint(destination_, amount_);
    }

    function cancelMint(uint256 mintId_) external onlyApprovedMinter {
        _cancelMint(msg.sender, mintId_);
    }

    function proposeRetrieval(uint256 amount_) external onlyApprovedMinter returns (uint256 retrievalId_) {
        uint256 outstandingValueSurplus_ = (amount_ * mintRatio()) / _ONE;

        // TODO: Fix `outstandingValueSurplus_` name and try to improve this function for use and readability.
        _revertIfUndercollateralized(msg.sender, outstandingValueSurplus_);

        retrievalId_ = uint256(keccak256(abi.encode(msg.sender, amount_, block.timestamp)));

        _totalCollateralPendingRetrieval[msg.sender] += amount_;
        _pendingRetrievals[msg.sender][retrievalId_] = amount_;

        emit RetrievalCreated(retrievalId_, msg.sender, amount_);
    }

    function burnM(address minter_, uint256 maxAmount_) external {
        updateIndex();

        _imposePenaltyIfMissedCollateralUpdates(minter_); // TODO: Only? What about undercollateralization?

        uint256 amount_ = _isApprovedMinter(minter_) // TODO: `isActiveMinter`.
            ? _repayForActiveMinter(minter_, maxAmount_)
            : _repayForInactiveMinter(minter_, maxAmount_);

        emit BurnExecuted(minter_, amount_, msg.sender);

        // Burn actual M tokens
        IMToken(_mToken).burn(msg.sender, amount_);
    }

    function deactivateMinter(address minter_) external returns (uint256 inactiveOwedM_) {
        if (_isApprovedMinter(minter_)) revert StillApprovedMinter();

        updateIndex();

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
        delete _principalOfActiveOwedM[minter_];
        delete _collaterals[minter_];
        delete _mintProposals[minter_];
        delete _unfrozenTimes[minter_];
    }

    function getPenaltyForMissedCollateralUpdates(address minter_) public view returns (uint256 penalty_) {
        (uint256 penaltyBase_, ) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);

        return (penaltyBase_ * penalty()) / _ONE;
    }

    /******************************************************************************************************************\
    |                                                Validator Functions                                               |
    \******************************************************************************************************************/

    function cancelMint(address minter_, uint256 mintId_) external onlyApprovedValidator {
        _cancelMint(minter_, mintId_);
    }

    function freezeMinter(address minter_) external onlyApprovedValidator returns (uint256 frozenUntil_) {
        frozenUntil_ = block.timestamp + SPOGRegistrarReader.getMinterFreezeTime(_spogRegistrar);

        emit MinterFrozen(minter_, _unfrozenTimes[minter_] = frozenUntil_);
    }

    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/

    function updateIndex() public override(IContinuousIndexing, ContinuousIndexing) returns (uint256 index_) {
        // TODO: Order of these matter if their rate models depend on the same utilization ratio / total supplies.
        index_ = super.updateIndex(); // Update Minter index.

        IMToken(_mToken).updateIndex(); // Update Earning index.

        // Mint M to Zero Vault
        uint256 excessOwedM_ = _getExcessOwedM();

        if (excessOwedM_ > 0) IMToken(_mToken).mint(_spogVault, excessOwedM_);
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function _imposePenalty(address minter_, uint256 penaltyBase_) internal {
        // TODO: The rate being charged for a late interval should be M per active owed M.
        // TODO: The rate being charged for a undercollateralization should be M per second per excess active owed M.
        // TODO: The above 2 are not remotely the same units, let alone the same rate. Fix.
        uint256 penalty_ = (penaltyBase_ * penalty()) / _ONE;
        uint256 penaltyPrincipal_ = _getPrincipalValue(penalty_);

        _principalOfActiveOwedM[minter_] += penaltyPrincipal_;
        _totalPrincipalOfActiveOwedM += penaltyPrincipal_;

        emit PenaltyImposed(minter_, penalty_);
    }

    function _imposePenaltyIfMissedCollateralUpdates(address minter_) internal {
        (uint256 penaltyBase_, uint256 penalizedUntil_) = _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);

        // Save penalization interval to not double charge for missed periods again
        _collaterals[minter_].penalizedUntil = penalizedUntil_;

        _imposePenalty(minter_, penaltyBase_);
    }

    function _imposePenaltyIfUndercollateralized(address minter_) internal {
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = activeOwedMOf(minter_);

        if (maxOwedM_ >= activeOwedM_) return;

        _imposePenalty(minter_, activeOwedM_ - maxOwedM_);
    }

    function _cancelMint(address minter_, uint256 mintId_) internal {
        if (_mintProposals[minter_].id != mintId_) revert InvalidMintProposal();

        delete _mintProposals[minter_];

        emit MintCanceled(mintId_, msg.sender);
    }

    function _resolvePendingRetrievals(address minter_, uint256[] calldata retrievalIds_) internal {
        for (uint256 index_; index_ < retrievalIds_.length; ++index_) {
            uint256 retrievalId_ = retrievalIds_[index_];

            _totalCollateralPendingRetrieval[minter_] -= _pendingRetrievals[minter_][retrievalId_];

            delete _pendingRetrievals[minter_][retrievalId_];
        }
    }

    function _updateCollateral(address minter_, uint256 amount_, uint256 newTimestamp_) internal {
        MinterCollateral storage minterCollateral_ = _collaterals[minter_];

        uint256 lastUpdated_ = minterCollateral_.lastUpdated;

        if (newTimestamp_ < lastUpdated_) revert StaleCollateralUpdate();

        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = newTimestamp_;
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
        uint256 threshold_ = SPOGRegistrarReader.getUpdateCollateralValidatorThreshold(_spogRegistrar);

        minTimestamp_ = block.timestamp;

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
                retrievalIds_,
                metadata_,
                timestamps_[index_]
            );

            // Check that validator is approved by SPOG.
            if (!SPOGRegistrarReader.isApprovedValidator(_spogRegistrar, validators_[index_])) continue;

            // Check that ECDSA or ERC1271 signatures for given digest are valid.
            if (!SignatureChecker.isValidSignature(validators_[index_], digest_, signatures_[index_])) continue;

            // Find minimum between all valid timestamps for valid signatures
            minTimestamp_ = _minIgnoreZero(minTimestamp_, timestamps_[index_]);

            --threshold_;
        }

        if (threshold_ > 0) revert NotEnoughValidSignatures();
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

    function _revertIfUndercollateralized(address minter_, uint256 additionalOwedM_) internal view {
        // TODO: fix.
        uint256 maxOwedM_ = _getMaxOwedM(minter_);
        uint256 activeOwedM_ = activeOwedMOf(minter_);

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

    function _getExcessOwedM() internal view returns (uint256 getExcessOwedM_) {
        uint256 totalMSupply_ = IMToken(_mToken).totalSupply();
        uint256 totalActiveOwedM_ = _getPresentValue(_totalPrincipalOfActiveOwedM);

        if (totalActiveOwedM_ > totalMSupply_) return totalActiveOwedM_ - totalMSupply_;
    }

    function _getMaxOwedM(address minter_) internal view returns (uint256 maxOwedM_) {
        MinterCollateral storage minterCollateral_ = _collaterals[minter_];

        // If collateral was not updated within the last interval, assume that minter_'s collateral is zero.
        return
            block.timestamp <= minterCollateral_.lastUpdated + updateCollateralInterval()
                ? ((minterCollateral_.amount - _totalCollateralPendingRetrieval[minter_]) * mintRatio()) / _ONE
                : 0;
    }

    function _getPresentValue(uint256 principalValue_) internal view returns (uint256 presentValue_) {
        return _getPresentAmount(principalValue_, currentIndex());
    }

    function _getPrincipalValue(uint256 presentValue_) internal view returns (uint256 principalValue_) {
        return _getPrincipalAmount(presentValue_, currentIndex());
    }

    function _getPenaltyBaseAndTimeForMissedCollateralUpdates(
        address minter_
    ) internal view returns (uint256 penaltyBase_, uint256 penalizedUntil_) {
        uint256 updateInterval_ = updateCollateralInterval();

        MinterCollateral storage minterCollateral_ = _collaterals[minter_];

        uint256 penalizeFrom_ = _max(minterCollateral_.lastUpdated, minterCollateral_.penalizedUntil);
        uint256 missedIntervals_ = (block.timestamp - penalizeFrom_) / updateInterval_;

        penaltyBase_ = missedIntervals_ * activeOwedMOf(minter_);
        penalizedUntil_ = penalizeFrom_ + (missedIntervals_ * updateInterval_);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ < b_ ? a_ : b_;
    }

    function _minIgnoreZero(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ == 0 ? b_ : _min(a_, b_);
    }

    function _max(uint256 a_, uint256 b_) internal pure returns (uint256 max_) {
        return a_ > b_ ? a_ : b_;
    }

    function _rate() internal view override returns (uint256 rate_) {
        address rateModel_ = SPOGRegistrarReader.getMinterRateModel(_spogRegistrar);

        (bool success_, bytes memory returnData_) = rateModel_.staticcall(
            abi.encodeWithSelector(IRateModel.rate.selector)
        );

        return success_ ? abi.decode(returnData_, (uint256)) : 0;
    }

    function _revertIfNotApprovedMinter(address minter_) internal view {
        if (!_isApprovedMinter(minter_)) revert NotApprovedMinter();
    }

    function _revertIfNotApprovedValidator(address validator_) internal view {
        if (!SPOGRegistrarReader.isApprovedValidator(_spogRegistrar, validator_)) revert NotApprovedValidator();
    }

    function _revertIfMinterFrozen(address minter_) internal view {
        if (block.timestamp < _unfrozenTimes[minter_]) revert FrozenMinter();
    }

    function _isApprovedMinter(address minter_) internal view returns (bool isApproved_) {
        return SPOGRegistrarReader.isApprovedMinter(_spogRegistrar, minter_);
    }

    function updateCollateralInterval() public view returns (uint256 updateCollateralInterval_) {
        return SPOGRegistrarReader.getUpdateCollateralInterval(_spogRegistrar);
    }

    function mintRatio() public view returns (uint256 getMintRatio_) {
        return SPOGRegistrarReader.getMintRatio(_spogRegistrar);
    }

    function penalty() public view returns (uint256 penalty_) {
        return SPOGRegistrarReader.getPenalty(_spogRegistrar);
    }

    function ONE() external pure returns (uint256 one_) {
        return _ONE;
    }

    function spogRegistrar() external view returns (address spogRegistrar_) {
        return _spogRegistrar;
    }

    function mToken() external view returns (address mToken_) {
        return _mToken;
    }

    function collateralOf(
        address minter_
    ) external view returns (uint256 collateral_, uint256 lastUpdated_, uint256 penalizedUntil_) {
        collateral_ = _collaterals[minter_].amount;
        lastUpdated_ = _collaterals[minter_].lastUpdated;
        penalizedUntil_ = _collaterals[minter_].penalizedUntil;
    }

    function mintProposalOf(
        address minter_
    ) external view returns (uint256 mintId_, address destination_, uint256 amount_, uint256 createdAt_) {
        mintId_ = _mintProposals[minter_].id;
        destination_ = _mintProposals[minter_].destination;
        amount_ = _mintProposals[minter_].amount;
        createdAt_ = _mintProposals[minter_].createdAt;
    }

    function unfrozenTimeOf(address minter_) external view returns (uint256 timestamp_) {
        return _unfrozenTimes[minter_];
    }

    function totalActiveOwedM() public view returns (uint256 totalActiveOwedM_) {
        return _getPresentValue(_totalPrincipalOfActiveOwedM);
    }

    function totalInactiveOwedM() public view returns (uint256 totalInactiveOwedM_) {
        return _totalInactiveOwedM;
    }

    function totalOwedM() external view returns (uint256 totalOwedM_) {
        return totalActiveOwedM() + totalInactiveOwedM();
    }

    function activeOwedMOf(address minter_) public view returns (uint256 activeOwedM_) {
        return _getPresentValue(_principalOfActiveOwedM[minter_]);
    }

    function inactiveOwedMOf(address minter_) external view returns (uint256 inactiveOwedM_) {
        return _inactiveOwedM[minter_];
    }

    function totalCollateralPendingRetrievalOf(address minter_) external view returns (uint256 collateral_) {
        return _totalCollateralPendingRetrieval[minter_];
    }

    function pendingRetrievalsOf(address minter_, uint256 retrievalId_) external view returns (uint256 collateral) {
        return _pendingRetrievals[minter_][retrievalId_];
    }
}
