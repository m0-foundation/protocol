// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SignatureChecker } from "./libs/SignatureChecker.sol";
import { InterestMath } from "./libs/InterestMath.sol";
import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";

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
    }

    // TODO bit-packing
    struct MintRequest {
        uint256 mintId; // TODO uint96 or uint48 if 2 additional fields
        address to;
        uint256 amount;
        uint256 createdAt;
    }

    /******************************************************************************************************************\
    |                                                Protocol variables                                                |
    \******************************************************************************************************************/

    /// @notice The EIP-712 typehash for updateCollateral method
    bytes32 public constant UPDATE_COLLATERAL_TYPEHASH =
        keccak256("UpdateCollateral(address minter,uint256 amount,uint256 timestamp,string metadata)");

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

    /// @notice The mint requests of minters, only 1 request per minter
    mapping(address minter => uint256 timestamp) public frozenUntil;

    /// @notice The total normalized principal (t0 principal value) for all minters
    uint256 public totalNormalizedPrincipal;

    /// @notice The normalized principal (t0 principal value) for each minter
    mapping(address minter => uint256 amount) public normalizedPrincipal;

    // TODO possibly bit-pack those 2 variables
    /// @notice The current M index for the protocol tracked for the entire market
    uint256 public mIndex;

    /// @notice The timestamp of the last time the M index was updated
    uint256 public lastAccrualTime;

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
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        if (block.timestamp > timestamp_ + updateInterval_) revert ExpiredTimestamp();

        address minter_ = msg.sender;

        CollateralBasic storage minterCollateral_ = collateral[minter_];
        if (minterCollateral_.lastUpdated > timestamp_) revert StaleTimestamp();

        // Validate that quorum of signatures was collected
        bytes32 updateCollateralDigest_ = _getUpdateCollateralDigest(minter_, amount_, metadata_, timestamp_);
        uint256 requiredQuorum_ = SPOGRegistrarReader.getUpdateCollateralQuorum(spogRegistrar);
        _revertIfInsufficientValidSignatures(updateCollateralDigest_, validators_, signatures_, requiredQuorum_);

        // accruePenalties(); // JIRA ticket https://mzerolabs.atlassian.net/jira/software/c/projects/WEB3/boards/10?selectedIssue=WEB3-396

        // Update collateral
        minterCollateral_.amount = amount_;
        minterCollateral_.lastUpdated = timestamp_;

        // _accruePenalties(); // JIRA ticket

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

        // _accruePenalties(); // JIRA ticket

        // Check that mint is sufficiently collateralized
        uint256 allowedDebt_ = _allowedDebtOf(minter_);
        uint256 currentDebt_ = _debtOf(minter_);
        if (currentDebt_ + amount_ > allowedDebt_) revert UndercollateralizedMint();

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

        uint256 activeAt_ = createdAt_ + SPOGRegistrarReader.getMintRequestQueueTime(spogRegistrar);
        if (now_ < activeAt_) revert PendingMintRequest();

        uint256 expiresAt_ = activeAt_ + SPOGRegistrarReader.getMintRequestTimeToLive(spogRegistrar);
        if (now_ > expiresAt_) revert ExpiredMintRequest();

        // _accruePenalties(); // JIRA ticket

        // Check that mint is sufficiently collateralized
        uint256 allowedDebt_ = _allowedDebtOf(minter_);
        uint256 currentDebt_ = _debtOf(minter_);
        if (currentDebt_ + amount_ > allowedDebt_) revert UndercollateralizedMint();

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
     * @dev If amount to burn is greater than minter's debt, burn all debt
     */
    function burn(address minter_, uint256 amount_) external {
        // _accruePenalties(); // JIRA ticket

        updateIndices();

        // Find minimum amount between given `amount_` to burn and minter's debt
        uint256 normalizedPrincipalDelta_ = _min(_principalValue(amount_), normalizedPrincipal[minter_]);
        uint256 amountDelta_ = _presentValue(normalizedPrincipalDelta_);

        normalizedPrincipal[minter_] -= normalizedPrincipalDelta_;
        totalNormalizedPrincipal -= normalizedPrincipalDelta_;

        // Burn actual M tokens
        IMToken(mToken).burn(msg.sender, amountDelta_);

        emit Burn(minter_, msg.sender, amountDelta_);
    }

    /**
     * @notice Returns the amount of M tokens that minter owes to the protocol
     */
    function debtOf(address minter_) external view returns (uint256) {
        return _debtOf(minter_);
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
        uint256 frozenUntil_ = block.timestamp + SPOGRegistrarReader.getMinterFreezeTime(spogRegistrar);

        emit MinterFrozen(minter_, frozenUntil[minter_] = frozenUntil_);
    }

    //
    //
    // proposeRedeem, redeem
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
    // updateIndices, updateBorrowIndex, updateStakingIndex
    // accruePenalties
    // mintRewardsToZeroHolders
    //
    //

    /**
     * @notice Updates indices
     */
    function updateIndices() public {
        // update Minting borrow index
        _updateBorrowIndex();

        // update Primary staking rate index
        _updateStakingIndex();

        // mintRewardsToZeroHolders();
    }

    function _updateBorrowIndex() internal {
        uint256 now_ = block.timestamp;
        uint256 timeElapsed_ = now_ - lastAccrualTime;
        if (timeElapsed_ > 0) {
            mIndex = _getIndex(timeElapsed_);
            lastAccrualTime = now_;
        }
    }

    function _updateStakingIndex() internal {}

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
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

    function _getIndex(uint256 timeElapsed_) internal view returns (uint256) {
        return InterestMath.multiply(
            mIndex,
            InterestMath.getContinuousRate(
                InterestMath.convertFromBasisPoints(_getBorrowRate()),
                timeElapsed_
            )
        );
    }

    function _allowedDebtOf(address minter_) internal view returns (uint256) {
        CollateralBasic storage minterCollateral_ = collateral[minter_];

        // if collateral was not updated on time, assume that minter_ CV is zero
        uint256 updateInterval_ = SPOGRegistrarReader.getUpdateCollateralInterval(spogRegistrar);
        if (minterCollateral_.lastUpdated + updateInterval_ < block.timestamp) return 0;

        uint256 mintRatio_ = SPOGRegistrarReader.getMintRatio(spogRegistrar);
        return (minterCollateral_.amount * mintRatio_) / ONE;
    }

    function _debtOf(address minter_) internal view returns (uint256) {
        uint256 principalValue_ = normalizedPrincipal[minter_];
        // return _presentValue(principalValue_) + penalties[minter];
        return _presentValue(principalValue_);
    }

    function _presentValue(uint256 principalValue_) internal view returns (uint256) {
        return InterestMath.multiply(principalValue_, _getIndex(block.timestamp - lastAccrualTime));
    }

    function _principalValue(uint256 presentValue_) internal view returns (uint256) {
        return InterestMath.divide(presentValue_, _getIndex(block.timestamp - lastAccrualTime));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _getBorrowRate() internal view returns (uint256 rate_) {
        return IInterestRateModel(SPOGRegistrarReader.getBorrowRateModel(spogRegistrar)).getRate();
    }

    function _revertIfNotApprovedMinter(address minter_) internal view {
        if (!SPOGRegistrarReader.isApprovedMinter(spogRegistrar, minter_)) revert NotApprovedMinter();
    }

    function _revertIfNotApprovedValidator(address validator_) internal view {
        if (!SPOGRegistrarReader.isApprovedValidator(spogRegistrar, validator_)) revert NotApprovedValidator();
    }
}
