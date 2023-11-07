// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { InterestMath } from "./libs/InterestMath.sol";

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "./interfaces/ISPOGRegistrar.sol";

import { StatelessERC712 } from "./StatelessERC712.sol";
import { MToken } from "./MToken.sol";

/**
 * @title Protocol
 * @author M^ZERO LABS_
 * @notice Core protocol of M^ZERO ecosystem. TODO Add description.
 */
contract Protocol is IProtocol, StatelessERC712 {
    // TODO bit-packing
    struct CollateralBasic {
        uint256 amount;
        uint256 lastUpdated;
        uint256 lastPenalized;
    }

    // TODO bit-packing
    struct MintRequest {
        uint256 mintId; // TODO uint96 or uint48 if 2 additional fields
        address to;
        uint256 amount;
        uint256 createdAt;
    }

    /******************************************************************************************************************\
    |                                                SPOG Variables and Lists Names                                    |
    \******************************************************************************************************************/

    /// @notice The minters' list name in SPOG
    bytes32 public constant MINTERS_LIST_NAME = "minters";

    /// @notice The validators' list name in SPOG
    bytes32 public constant VALIDATORS_LIST_NAME = "validators";

    /// @notice The name of parameter that defines number of signatures required for successful collateral update
    bytes32 public constant UPDATE_COLLATERAL_QUORUM = "updateCollateral_quorum";

    /// @notice The name of parameter in SPOG that required interval to update collateral
    bytes32 public constant UPDATE_COLLATERAL_INTERVAL = "updateCollateral_interval";

    /// @notice The name of parameter in SPOG that defines the time to wait for mint request to be processed
    bytes32 public constant MINT_DELAY = "mint_delay";

    /// @notice The name of parameter in SPOG that defines the time while mint request can still be processed
    bytes32 public constant MINT_TTL = "mint_ttl";

    /// @notice The name of parameter in SPOG that defines the time to freeze minter
    bytes32 public constant MINTER_FREEZE_TIME = "minter_freeze_time";

    /// @notice The name of parameter in SPOG that defines the M rate model contract
    bytes32 public constant M_RATE_MODEL = "m_rate_model";

    /// @notice The name of parameter in SPOG that defines the mint ratio
    bytes32 public constant MINT_RATIO = "mint_ratio"; // bps

    /// @notice The name of parameter in SPOG that defines the penaty ratio
    bytes32 public constant PENALTY = "penalty"; // bps

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    /// @notice The EIP-712 typehash for updateCollateral method
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)");

    /// @notice The scale for M index
    uint256 public constant INDEX_BASE_SCALE = 1e18;

    /// @notice TODO The scale for collateral, most likely will be passed in cents
    uint256 public constant COLLATERAL_BASE_SCALE = 1e2;

    /// @notice Descaler for variables in basis points
    uint256 public constant ONE = 10_000; // 100% in basis points.

    /// @notice The address of SPOG Registrar Contract
    address public immutable spogRegistrar;

    /// @notice The address of M token
    address public immutable mToken;

    /// @notice The collateral information of minters
    mapping(address minter => CollateralBasic basic) public collateral;

    /// @notice The mint requests of minters, only 1 request per minter
    mapping(address minter => MintRequest request) public mintRequests;

    /// @notice The time until minter will stay frozen
    mapping(address minter => uint256 timestamp) public frozenUntil;

    /// @notice The total normalized principal (t0 principal value) for all minters
    uint256 public totalNormalizedPrincipal;

    /// @notice The normalized principal (t0 principal value) for each minter
    mapping(address minter => uint256 amount) public normalizedPrincipal;

    /// @notice The penalties for each minter
    mapping(address minter => uint256 amount) internal _penalty;

    /// @notice The total amount of charged penalties for all minters
    uint256 public totalChargedPenalties;

    /// @notice The total amount of penalties repaid by all minters
    uint256 public totalRepaidPenalties;

    // TODO possibly bit-pack those 2 variables
    /// @notice The current M index for the protocol tracked for the entire market
    uint256 public mIndex;

    /// @notice The timestamp of the last time the M index was updated
    uint256 public lastAccrualTime;

    modifier onlyApprovedMinter() {
        if (!_isApprovedMinter(msg.sender)) revert NotApprovedMinter();

        _;
    }

    modifier onlyApprovedValidator() {
        if (!_isApprovedValidator(msg.sender)) revert NotApprovedValidator();

        _;
    }

    /**
     * @notice Constructor.
     * @param spogRegistrar_ The address of SPOG
     */
    constructor(address spogRegistrar_, address mToken_) StatelessERC712("Protocol") {
        spogRegistrar = spogRegistrar_;
        mToken = mToken_;

        mIndex = 1e18;
        lastAccrualTime = block.timestamp;
    }

    /******************************************************************************************************************\
    |                                                Minter Functions                                                  |
    \******************************************************************************************************************/

    /**
     * @notice Updates collateral for minters
     * @param amount_ The amount of collateral
     * @param timestamp_ The timestamp of the update
     * @param metadata_ The metadata of the update, reserved for future informational use
     * @param validators_ The list of validators
     * @param signatures_ The list of signatures
     */
    function updateCollateral(
        uint256 amount_,
        uint256 timestamp_,
        string memory metadata_,
        address[] calldata validators_,
        bytes[] calldata signatures_
    ) external onlyApprovedMinter {
        if (validators_.length != signatures_.length) revert InvalidSignaturesLength();

        // Timestamp sanity checks
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        if (block.timestamp / updateInterval_ != timestamp_ / updateInterval_) revert ExpiredTimestamp();
        // if (block.timestamp > timestamp_ + updateInterval_) revert ExpiredTimestamp();

        address minter_ = msg.sender;

        CollateralBasic storage minterCollateral_ = collateral[minter_];
        if (minterCollateral_.lastUpdated > timestamp_) revert StaleTimestamp();

        // Validate that quorum of signatures was collected
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = _getUpdateCollateralQuorum();
        _revertIfInsufficientValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // Accrue penalties before update collateral
        _accruePenalty(minter_);

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        emit CollateralUpdated(minter_, amount_, timestamp_, metadata_);
    }

    /**
     * @notice Proposes minting of M tokens
     * @param amount_ The amount of M tokens to mint
     * @param to_ The address to mint to
     */
    function proposeMint(uint256 amount_, address to_) external onlyApprovedMinter returns (uint256) {
        address minter_ = msg.sender;
        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < frozenUntil[msg.sender]) revert FrozenMinter();

        // Check if there is a pending non-expired mint request
        // uint256 expiresAt_ = mintRequest_.createdAt + _getMintRequestTimeToLive();
        // if (mintRequest_.amount > 0 && now_ < expiresAt_) revert OnlyOneMintRequestAllowed();

        // Accrue penalties to correctly calculate current minter's outstandingValue
        _accruePenalty(minter_);

        // Check that mint is sufficiently collateralized
        uint256 allowedOutstandingValue_ = _allowedOutstandingValue(minter_, false);
        uint256 currentOutstandingValue_ = _outstandingValue(minter_);
        if (currentOutstandingValue_ + amount_ > allowedOutstandingValue_) revert UndercollateralizedMint();

        uint256 mintId_ = uint256(keccak256(abi.encode(minter_, amount_, to_, now_, gasleft())));

        // Save mint request info
        MintRequest storage mintRequest_ = mintRequests[minter_];
        mintRequest_.mintId = mintId_;
        mintRequest_.to = to_;
        mintRequest_.amount = amount_;
        mintRequest_.createdAt = now_;

        emit MintRequestedCreated(mintId_, minter_, amount_, to_);

        return mintId_;
    }

    /**
     * @notice Executes minting of M tokens
     * @param mintId_ The id of outstanding mint request for minter
     */
    function mint(uint256 mintId_) external onlyApprovedMinter {
        address minter_ = msg.sender;

        uint256 now_ = block.timestamp;

        // Check is minter is frozen
        if (now_ < frozenUntil[minter_]) revert FrozenMinter();

        MintRequest storage mintRequest_ = mintRequests[minter_];

        // Inconsistent mintId_
        if (mintRequest_.mintId != mintId_) revert InvalidMintRequest();

        // Check that request is executable
        (uint256 amount_, uint256 createdAt_, address to_) = (
            mintRequest_.amount,
            mintRequest_.createdAt,
            mintRequest_.to
        );

        uint256 activeAt_ = createdAt_ + _getMintRequestQueueTime();
        if (now_ < activeAt_) revert PendingMintRequest();

        uint256 expiresAt_ = activeAt_ + _getMintRequestTimeToLive();
        if (now_ > expiresAt_) revert ExpiredMintRequest();

        _accruePenalty(minter_);

        // Check that mint is sufficiently collateralized
        uint256 allowedOutstandingValue_ = _allowedOutstandingValue(minter_, false);
        uint256 currentOutstandingValue_ = _outstandingValue(minter_);
        if (currentOutstandingValue_ + amount_ > allowedOutstandingValue_) revert UndercollateralizedMint();

        updateIndices();

        // Delete mint request
        delete mintRequests[minter_];

        // Adjust normalized principal for minter
        uint256 normalizedPrincipal_ = _principalValue(amount_);
        normalizedPrincipal[minter_] += normalizedPrincipal_;
        totalNormalizedPrincipal += normalizedPrincipal_;

        // Mint actual M tokens
        IMToken(mToken).mint(to_, amount_);

        emit MintRequestExecuted(mintId_, minter_, amount_, to_);
    }

    /**
     * @notice Cancels minting request for minter
     * @param mintId_ The id of outstanding mint request
     */
    function cancel(uint256 mintId_) external onlyApprovedMinter {
        _cancel(msg.sender, mintId_);
    }

    /**
     * @notice Burns M tokens
     * @param minter_ The address of the minter to burn M tokens for
     * @param amount_ The max amount of M tokens to burn
     * @dev If amount to burn is greater than minter's outstandingValue including penalties, burn all outstandingValue
     */
    function burn(address minter_, uint256 amount_) external {
        _accruePenalty(minter_);

        updateIndices();

        uint256 repaidPenaltyAmount_ = _repayPenalty(minter_, amount_);
        uint256 repaidPrincipalAmount_ = _repayPrincipal(minter_, amount_ - repaidPenaltyAmount_);
        uint256 totalRepaid_ = repaidPenaltyAmount_ + repaidPrincipalAmount_;

        // Burn actual M tokens
        IMToken(mToken).burn(msg.sender, totalRepaid_);

        emit Burn(minter_, msg.sender, totalRepaid_);
    }

    /**
     * @notice Returns the amount of M tokens that minter owes to the protocol
     */
    function outstandingValue(address minter_) external view returns (uint256) {
        return _outstandingValue(minter_);
    }

    /******************************************************************************************************************\
    |                                                Validator Functions                                               |
    \******************************************************************************************************************/

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param minter_ The address of the minter to cancel minting request for
     * @param mintId_ The id of outstanding mint request
     */
    function cancel(address minter_, uint256 mintId_) external onlyApprovedValidator {
        _cancel(minter_, mintId_);
    }

    /**
     * @notice Freezes minter
     * @param minter_ The address of the minter to freeze
     */
    function freeze(address minter_) external onlyApprovedValidator {
        uint256 frozenUntil_ = block.timestamp + _getMinterFreezeTime();

        emit MinterFrozen(minter_, frozenUntil[minter_] = frozenUntil_);
    }

    //
    //
    // proposeRetrieve, retrieve
    // removeMinter
    //
    //
    /******************************************************************************************************************\
    |                                                Primary Functions                                                 |
    \******************************************************************************************************************/
    //
    //
    // stake
    // withdraw
    //
    //
    /******************************************************************************************************************\
    |                                                Brains Functions                                                  |
    \******************************************************************************************************************/
    //
    //
    // mintRewardsToZeroHolders
    //
    //

    /**
     * @notice Updates M and Staking indices
     */
    function updateIndices() public {
        // Update M index
        _updateMIndex();

        // Update Primary staking rate index
        _updateStakingIndex();

        // mintRewardsToZeroHolders();
    }

    function _updateMIndex() internal {
        uint256 now_ = block.timestamp;
        uint256 timeElapsed_ = now_ - lastAccrualTime;
        if (timeElapsed_ > 0) {
            mIndex = _getMIndex(timeElapsed_);
            lastAccrualTime = now_;
        }
    }

    function _updateStakingIndex() internal {}

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @notice Cancels minting request for minter
     * @param minter_ The address of the minter to cancel minting request for
     * @param mintId_ The id of outstanding mint request
     */
    function _cancel(address minter_, uint256 mintId_) internal {
        if (mintRequests[minter_].mintId != mintId_) revert InvalidMintRequest();

        delete mintRequests[minter_];

        emit MintRequestCanceled(mintId_, minter_, msg.sender);
    }

    /**
     * @notice Repays penalties for a minter up to given amount
     * @param minter_ The address of the minter
     * @param amount_ The max amount of penalties to repay
     * @return The amount of penalties repaid
     */
    function _repayPenalty(address minter_, uint256 amount_) internal returns (uint256) {
        if (_penalty[minter_] == 0) return 0;

        uint256 penaltyDeduction_ = _penalty[minter_] > amount_ ? amount_ : _penalty[minter_];

        _penalty[minter_] -= penaltyDeduction_;
        // totalPenalties -= penaltyDeduction_;
        totalRepaidPenalties += penaltyDeduction_;

        emit PenaltyRepaid(minter_, msg.sender, penaltyDeduction_);

        return penaltyDeduction_;
    }

    /**
     * @notice Repays principal for a minter up to given amount
     * @param minter_ The address of the minter
     * @param amount_ The max amount of minter's `interestAdjustedMintValue` to repay
     * @return The amount of minter's `interestAdjustedMintValue` that was repaid
     */
    function _repayPrincipal(address minter_, uint256 amount_) internal returns (uint256) {
        if (amount_ == 0 || normalizedPrincipal[minter_] == 0) return 0;

        // Find min between given `amount_` to burn and minter's current outstandingValue
        uint256 normalizedPrincipalDelta_ = _min(_principalValue(amount_), normalizedPrincipal[minter_]);
        uint256 amountDelta_ = _interestAdjustedMintValue(normalizedPrincipalDelta_);

        normalizedPrincipal[minter_] -= normalizedPrincipalDelta_;
        totalNormalizedPrincipal -= normalizedPrincipalDelta_;

        emit PrincipalRepaid(minter_, msg.sender, amountDelta_);

        return amountDelta_;
    }

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
            bool authorized_ = _isApprovedValidator(validator_);
            if (!authorized_) continue;

            // Check that ECDSA or ERC1271 signatures for given digest are valid
            bool valid_ = SignatureChecker.isValidSignature(validator_, digest_, signatures_[index_]);
            if (!valid_) continue;

            // Stop processing if quorum was reached
            if (++validSignaturesNum_ == requiredQuorum_) return;
        }

        revert NotEnoughValidSignatures();
    }

    /**
     * @notice Returns the current value M index
     * @param timeElapsed_ The time elapsed since last update of index
     */
    function _getMIndex(uint timeElapsed_) internal view returns (uint256) {
        uint256 rate_ = _getBorrowRate();
        return timeElapsed_ > 0 ? InterestMath.calculateIndex(mIndex, rate_, timeElapsed_) : mIndex;
    }

    /**
     * @notice Returns the maximum allowed outstanding value for minter
     * @dev allowedOutstandingValue = collateral * mintRatio
     * @param minter_ The address of the minter
     */
    function _allowedOutstandingValue(
        address minter_,
        bool allowUpdateInPreviousInterval_
    ) internal view returns (uint256) {
        CollateralBasic storage minterCollateral_ = collateral[minter_];

        // if collateral was not updated on time, assume that minter_ CV is zero
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        uint256 lastUpdatedInterval_ = minterCollateral_.lastUpdated / updateInterval_;
        uint256 nowInterval_ = block.timestamp / updateInterval_;

        // TODO make sure it is safe if interval period changes
        bool expiredCollateralUpdate_ = allowUpdateInPreviousInterval_
            ? nowInterval_ - lastUpdatedInterval_ > 1
            : nowInterval_ != lastUpdatedInterval_;

        if (expiredCollateralUpdate_) return 0;

        uint256 mintRatio_ = _getMintRatio();
        return (minterCollateral_.amount * mintRatio_) / ONE;
    }

    /**
     * @notice Returns the current value of minter's outstanding value
     * @dev outstandingValue = normalizedPrincipal * mIndex + penalties
     * @param minter_ The address of the minter
     */
    function _outstandingValue(address minter_) internal view returns (uint256) {
        uint256 principal_ = normalizedPrincipal[minter_];
        return _interestAdjustedMintValue(principal_) + _getPenalty(minter_);
    }

    /**
     * @notice Returns the current value of minter's interest adjusted mint value
     * @dev interestAdjustedMintValue = normalizedPrincipal * mIndex
     * @param minter_ The address of the minter
     */
    function _interestAdjustedMintValue(address minter_) internal view returns (uint256) {
        return _interestAdjustedMintValue(normalizedPrincipal[minter_]);
    }

    /**
     * @notice Returns the current value interest adjusted value for normalized principal
     * @dev interestAdjustedMintValue = principal * mIndex
     * @param principal_ The principal value
     */
    function _interestAdjustedMintValue(uint256 principal_) internal view returns (uint256) {
        uint256 timeElapsed_ = block.timestamp - lastAccrualTime;
        return (principal_ * _getMIndex(timeElapsed_)) / INDEX_BASE_SCALE;
    }

    /**
     * @notice Returns the current value of minter's principal value
     * @dev normalizedPrincipal = amount  / mIndex
     * @param amount_ The amount of M tokens to convert to principal value
     */
    function _principalValue(uint256 amount_) internal view returns (uint256) {
        uint256 timeElapsed_ = block.timestamp - lastAccrualTime;
        return (amount_ * INDEX_BASE_SCALE) / _getMIndex(timeElapsed_);
    }

    /**
     * @notice Accrues penalties for minter for
     *   1. not updating collateral on time, once per `updateCollateralInterval`
     *   2. maintaing exessive outstandingValue
     * @dev Charged only once per interval to avoid double-charging
     * @param minter_ The address of the minter
     */
    function _accruePenalty(address minter_) internal {
        uint256 extraPenalty_ = _getUnaccruedPenalty(minter_);

        _penalty[minter_] += extraPenalty_;
        // totalChargedPenalties += extraPenalty_;
        collateral[minter_].lastPenalized = block.timestamp;

        emit PenaltyCharged(minter_, extraPenalty_);
    }

    function getPenalty(address minter_) external view returns (uint256) {
        return _getPenalty(minter_);
    }

    function _getPenalty(address minter_) internal view returns (uint256) {
        return _penalty[minter_] + _getUnaccruedPenalty(minter_);
    }

    function _getUnaccruedPenalty(address minter_) internal view returns (uint256) {
        uint256 updateInterval_ = _getUpdateCollateralInterval();
        CollateralBasic storage minterCollateral_ = collateral[minter_];

        // Minter_ was already penalized in this period, do not penalize twice
        if (minterCollateral_.lastPenalized / updateInterval_ == block.timestamp / updateInterval_) return 0;

        // NOTE: use only already accrued and charged penalties per calculation
        uint256 outstandingValue_ = _interestAdjustedMintValue(minter_) + _penalty[minter_];
        // If CV was not updated on time, assume that minter_ CV is zero
        uint256 allowedOutstandingValue_ = _allowedOutstandingValue(minter_, true);

        // Minter does not maintain excessive outstanding value
        if (outstandingValue_ <= allowedOutstandingValue_) return 0;

        uint256 excessiveOustandingValue_ = outstandingValue_ - allowedOutstandingValue_;
        return (excessiveOustandingValue_ * _getPenaltyRatio()) / ONE;
    }

    function _fromBytes32(bytes32 value_) internal pure returns (address) {
        return address(uint160(uint256(value_)));
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ < b_ ? a_ : b_;
    }

    /******************************************************************************************************************\
    |                                                SPOG Accessors                                                    |
    \******************************************************************************************************************/

    function _isApprovedMinter(address minter_) internal view returns (bool) {
        return ISPOGRegistrar(spogRegistrar).listContains(MINTERS_LIST_NAME, minter_);
    }

    function _isApprovedValidator(address validator_) internal view returns (bool) {
        return ISPOGRegistrar(spogRegistrar).listContains(VALIDATORS_LIST_NAME, validator_);
    }

    function _getUpdateCollateralInterval() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(UPDATE_COLLATERAL_INTERVAL));
    }

    function _getUpdateCollateralQuorum() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(UPDATE_COLLATERAL_QUORUM));
    }

    function _getMintRequestQueueTime() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(MINT_DELAY));
    }

    function _getMintRequestTimeToLive() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(MINT_TTL));
    }

    function _getMinterFreezeTime() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(MINTER_FREEZE_TIME));
    }

    function _getBorrowRate() internal view returns (uint256) {
        address rateContract_ = _fromBytes32(ISPOGRegistrar(spogRegistrar).get(M_RATE_MODEL));
        return IInterestRateModel(rateContract_).getRate();
    }

    function _getMintRatio() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(MINT_RATIO));
    }

    function _getPenaltyRatio() internal view returns (uint256) {
        return uint256(ISPOGRegistrar(spogRegistrar).get(PENALTY));
    }
}
