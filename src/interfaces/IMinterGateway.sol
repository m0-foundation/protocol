// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC712 } from "../../lib/common/src/interfaces/IERC712.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

/**
 * @title  Minter Gateway Interface.
 * @author M^0 Labs
 */
interface IMinterGateway is IContinuousIndexing, IERC712 {
    /* ============ Events ============ */

    /**
     * @notice Emitted when M tokens are burned and an inactive minter's owed M balance decreased.
     * @param  minter The address of the minter.
     * @param  amount The amount of M tokens burned.
     * @param  payer  The address of the payer.
     */
    event BurnExecuted(address indexed minter, uint240 amount, address indexed payer);

    /**
     * @notice Emitted when M tokens are burned and an active minter's owed M balance decreased.
     * @param  minter          The address of the minter.
     * @param  principalAmount The principal amount of M tokens burned.
     * @param  amount          The amount of M tokens burned.
     * @param  payer           The address of the payer.
     */
    event BurnExecuted(address indexed minter, uint112 principalAmount, uint240 amount, address indexed payer);

    /**
     * @notice Emitted when a minter's collateral is updated.
     * @param  minter                           Address of the minter
     * @param  collateral                       The latest amount of collateral
     * @param  totalResolvedCollateralRetrieval The total collateral amount of outstanding retrievals resolved.
     * @param  metadataHash                     The hash of some metadata reserved for future informational use.
     * @param  timestamp                        The timestamp of the collateral update,
     *                                          minimum of given validators' signatures.
     */
    event CollateralUpdated(
        address indexed minter,
        uint240 collateral,
        uint240 totalResolvedCollateralRetrieval,
        bytes32 indexed metadataHash,
        uint40 timestamp
    );

    /**
     * @notice Emitted when a minter is activated.
     * @param  minter Address of the minter that was activated
     * @param  caller Address who called the function
     */
    event MinterActivated(address indexed minter, address indexed caller);

    /**
     * @notice Emitted when a minter is deactivated.
     * @param  minter        Address of the minter that was deactivated.
     * @param  inactiveOwedM Amount of M tokens owed by the minter (in an inactive state).
     * @param  caller        Address who called the function.
     */
    event MinterDeactivated(address indexed minter, uint240 inactiveOwedM, address indexed caller);

    /**
     * @notice Emitted when a minter is frozen.
     * @param  minter      Address of the minter that was frozen
     * @param  frozenUntil Timestamp until the minter is frozen
     */
    event MinterFrozen(address indexed minter, uint40 frozenUntil);

    /**
     * @notice Emitted when a mint proposal is canceled.
     * @param  mintId    The id of the canceled mint proposal.
     * @param  minter    The address of the minter for which the mint was canceled.
     * @param  canceller The address of the validator who canceled the mint proposal.
     */
    event MintCanceled(uint48 indexed mintId, address indexed minter, address indexed canceller);

    /**
     * @notice Emitted when a mint proposal is executed.
     * @param  mintId          The id of the executed mint proposal.
     * @param  minter          The address of the minter that executed the mint.
     * @param  principalAmount The principal amount of M tokens minted.
     * @param  amount          The amount of M tokens minted.
     */
    event MintExecuted(uint48 indexed mintId, address indexed minter, uint112 principalAmount, uint240 amount);

    /**
     * @notice Emitted when a mint proposal is created.
     * @param  mintId      The id of mint proposal.
     * @param  minter      The address of the minter that proposed the mint.
     * @param  amount      The amount of M tokens to mint.
     * @param  destination The address to mint to.
     */
    event MintProposed(uint48 indexed mintId, address indexed minter, uint240 amount, address indexed destination);

    /**
     * @notice Emitted when a penalty is imposed on `minter` for missed update collateral intervals.
     * @param  minter          The address of the minter.
     * @param  missedIntervals The number of update intervals missed.
     * @param  penaltyAmount   The present amount of penalty charge.
     */
    event MissedIntervalsPenaltyImposed(address indexed minter, uint40 missedIntervals, uint240 penaltyAmount);

    /**
     * @notice Emitted when a penalty is imposed on `minter` for undercollateralization.
     * @param  minter        The address of the minter.
     * @param  excessOwedM   The present amount of owed M in excess of allowed owed M.
     * @param  timeSpan      The span of time over which the undercollateralization penalty was applied.
     * @param  penaltyAmount The present amount of penalty charge.
     */
    event UndercollateralizedPenaltyImposed(
        address indexed minter,
        uint240 excessOwedM,
        uint40 timeSpan,
        uint240 penaltyAmount
    );

    /**
     * @notice Emitted when a collateral retrieval proposal is created.
     * @param  retrievalId The id of retrieval proposal.
     * @param  minter      The address of the minter.
     * @param  amount      The amount of collateral to retrieve.
     */
    event RetrievalCreated(uint48 indexed retrievalId, address indexed minter, uint240 amount);

    /**
     * @notice Emitted when a collateral retrieval proposal is resolved.
     * @param  retrievalId The id of retrieval proposal.
     * @param  minter      The address of the minter.
     */
    event RetrievalResolved(uint48 indexed retrievalId, address indexed minter);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when calling `activateMinter` with a minter who was previously deactivated.
    error DeactivatedMinter();

    /// @notice Emitted when repay will burn more M than the repay specified.
    error ExceedsMaxRepayAmount(uint240 amount, uint240 maxAmount);

    /// @notice Emitted when calling `mintM` with a proposal that was created more than `mintDelay + mintTTL` time ago.
    error ExpiredMintProposal(uint40 deadline);

    /// @notice Emitted when calling `mintM` or `proposeMint` by a minter who was frozen by validator.
    error FrozenMinter();

    /// @notice Emitted when calling `updateCollateral` with any validator timestamp in the future.
    error FutureTimestamp();

    /// @notice Emitted when calling a function only allowed for active minters.
    error InactiveMinter();

    /// @notice Emitted when calling `cancelMint` or `mintM` with invalid `mintId`.
    error InvalidMintProposal();

    /// @notice Emitted when calling `updateCollateral` if `validators` addresses are not ordered in ascending order.
    error InvalidSignatureOrder();

    /// @notice Emitted when calling `activateMinter` if minter was not approved by TTG.
    error NotApprovedMinter();

    /// @notice Emitted when calling `cancelMint` or `freezeMinter` if `validator` was not approved by TTG.
    error NotApprovedValidator(address validator);

    /// @notice Emitted when calling `updateCollateral` if `validatorThreshold` of signatures was not reached.
    error NotEnoughValidSignatures(uint256 validSignatures, uint256 requiredThreshold);

    /// @notice Emitted when principal of total owed M (active and inactive) will overflow a `type(uint112).max`.
    error OverflowsPrincipalOfTotalOwedM();

    /// @notice Emitted when calling `mintM` if `mintDelay` time has not passed yet.
    error PendingMintProposal(uint40 activeTimestamp);

    /// @notice Emitted when calling `proposeRetrieval` if sum of all outstanding retrievals
    ///         Plus new proposed retrieval amount is greater than collateral.
    error RetrievalsExceedCollateral(uint240 totalPendingRetrievals, uint240 collateral);

    /// @notice Emitted when calling `updateCollateral`
    ///         If `validators`, `signatures`, `timestamps` lengths do not match.
    error SignatureArrayLengthsMismatch();

    /// @notice Emitted when updating collateral with a timestamp earlier than allowed.
    error StaleCollateralUpdate(uint40 newTimestamp, uint40 earliestAllowedTimestamp);

    /// @notice Emitted when calling `updateCollateral` with any validator timestamp older than the last signature
    ///         timestamp for that minter and validator.
    error OutdatedValidatorTimestamp(address validator, uint256 timestamp, uint256 lastSignatureTimestamp);

    /// @notice Emitted when calling `deactivateMinter` with a minter still approved in TTG Registrar.
    error StillApprovedMinter();

    /**
     * @notice Emitted when calling `proposeMint`, `mintM`, `proposeRetrieval`
     *         If minter position becomes undercollateralized.
     * @dev    `activeOwedM` is a `uint256` because it may represent some resulting owed M from computations.
     */
    error Undercollateralized(uint256 activeOwedM, uint256 maxAllowedOwedM);

    /// @notice Emitted when calling `burnM` if amount is 0.
    error ZeroBurnAmount();

    /// @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    /// @notice Emitted when calling `proposeMint` if amount is 0.
    error ZeroMintAmount();

    /// @notice Emitted when calling `proposeMint` if destination is 0x0.
    error ZeroMintDestination();

    /// @notice Emitted when calling `proposeRetrieval` if collateral is 0.
    error ZeroRetrievalAmount();

    /// @notice Emitted in constructor if TTG Registrar is 0x0.
    error ZeroTTGRegistrar();

    /// @notice Emitted in constructor if TTG Distribution Vault is set to 0x0 in TTG Registrar.
    error ZeroTTGVault();

    /// @notice Emitted when calling `updateCollateral` with any validator timestamp of 0.
    error ZeroTimestamp();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates collateral for minters
     * @param  collateral   The amount of collateral
     * @param  retrievalIds The list of active proposeRetrieval requests to close
     * @param  metadataHash The hash of metadata of the collateral update, reserved for future informational use
     * @param  validators   The list of validators
     * @param  timestamps   The list of timestamps of validators' signatures
     * @param  signatures   The list of signatures
     * @return minTimestamp The minimum timestamp of all validators' signatures
     */
    function updateCollateral(
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        address[] calldata validators,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external returns (uint40 minTimestamp);

    /**
     * @notice Proposes retrieval of minter's off-chain collateral
     * @param  collateral  The amount of collateral to retrieve
     * @return retrievalId The unique id of created retrieval proposal
     */
    function proposeRetrieval(uint256 collateral) external returns (uint48 retrievalId);

    /**
     * @notice Proposes minting of M tokens
     * @param  amount      The amount of M tokens to mint
     * @param  destination The address to mint to
     * @return mintId      The unique id of created mint proposal
     */
    function proposeMint(uint256 amount, address destination) external returns (uint48 mintId);

    /**
     * @notice Executes minting of M tokens
     * @param  mintId          The id of outstanding mint proposal for minter
     * @return principalAmount The amount of principal of owed M minted.
     * @return amount          The amount of M tokens minted.
     */
    function mintM(uint256 mintId) external returns (uint112 principalAmount, uint240 amount);

    /**
     * @notice Burns M tokens
     * @dev    If amount to burn is greater than minter's owedM including penalties, burn all up to owedM.
     * @param  minter          The address of the minter to burn M tokens for.
     * @param  maxAmount       The max amount of M tokens to burn.
     * @return principalAmount The amount of principal of owed M burned.
     * @return amount          The amount of M tokens burned.
     */
    function burnM(address minter, uint256 maxAmount) external returns (uint112 principalAmount, uint240 amount);

    /**
     * @notice Burns M tokens
     * @dev    If amount to burn is greater than minter's owedM including penalties, burn all up to owedM.
     * @param  minter             The address of the minter to burn M tokens for.
     * @param  maxPrincipalAmount The max amount of principal of owed M to burn.
     * @param  maxAmount          The max amount of M tokens to burn.
     * @return principalAmount    The amount of principal of owed M burned.
     * @return amount             The amount of M tokens burned.
     */
    function burnM(
        address minter,
        uint256 maxPrincipalAmount,
        uint256 maxAmount
    ) external returns (uint112 principalAmount, uint240 amount);

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param  minter The address of the minter to cancelMint minting request for
     * @param  mintId The id of outstanding mint request
     */
    function cancelMint(address minter, uint256 mintId) external;

    /**
     * @notice Freezes minter
     * @param  minter      The address of the minter to freeze
     * @return frozenUntil The timestamp until which minter is frozen
     */
    function freezeMinter(address minter) external returns (uint40 frozenUntil);

    /**
     * @notice Activate an approved minter.
     * @dev    MUST revert if `minter` is not recorded as an approved minter in TTG Registrar.
     * @dev    MUST revert if `minter` has been deactivated.
     * @param  minter The address of the minter to activate
     */
    function activateMinter(address minter) external;

    /**
     * @notice Deactivates an active minter.
     * @dev    MUST revert if the minter is still approved.
     * @dev    MUST revert if the minter is not active.
     * @param  minter        The address of the minter to deactivate.
     * @return inactiveOwedM The inactive owed M for the deactivated minter.
     */
    function deactivateMinter(address minter) external returns (uint240 inactiveOwedM);

    /* ============ View/Pure Functions ============ */

    /// @notice The address of M token
    function mToken() external view returns (address);

    /// @notice The address of TTG Registrar contract.
    function ttgRegistrar() external view returns (address);

    /// @notice The address of TTG Vault contract.
    function ttgVault() external view returns (address);

    /// @notice The last saved value of Minter rate.
    function minterRate() external view returns (uint32);

    /// @notice The principal of total owed M for all active minters.
    function principalOfTotalActiveOwedM() external view returns (uint112);

    /// @notice The total owed M for all active minters.
    function totalActiveOwedM() external view returns (uint240);

    /// @notice The total owed M for all inactive minters.
    function totalInactiveOwedM() external view returns (uint240);

    /// @notice The total owed M for all minters.
    function totalOwedM() external view returns (uint240);

    /// @notice The difference between total owed M and M token total supply.
    function excessOwedM() external view returns (uint240);

    /// @notice The principal of active owed M of minter.
    function principalOfActiveOwedMOf(address minter_) external view returns (uint112);

    /// @notice The active owed M of minter.
    function activeOwedMOf(address minter) external view returns (uint240);

    /**
     * @notice The max allowed active owed M of minter taking into account collateral amount and retrieval proposals.
     * @dev    This is the only present value that requires a `uint256` since it is the result of a multiplication
     *         between a `uint240` and a value that has a max of `65,000` (the mint ratio).
     */
    function maxAllowedActiveOwedMOf(address minter) external view returns (uint256);

    /// @notice The inactive owed M of deactivated minter.
    function inactiveOwedMOf(address minter) external view returns (uint240);

    /// @notice The collateral of a given minter.
    function collateralOf(address minter) external view returns (uint240);

    /// @notice The timestamp of the last collateral update of minter.
    function collateralUpdateTimestampOf(address minter) external view returns (uint40);

    /// @notice The timestamp after which an additional penalty for a missed update interval will be charged.
    function collateralPenaltyDeadlineOf(address minter) external view returns (uint40);

    /// @notice The timestamp after which the minter's collateral is assumed to be 0 due to a missed update.
    function collateralExpiryTimestampOf(address minter) external view returns (uint40);

    /// @notice The timestamp until which minter is already penalized for missed collateral updates.
    function penalizedUntilOf(address minter) external view returns (uint40);

    /// @notice The timestamp when `minter` created their latest retrieval proposal.
    function latestProposedRetrievalTimestampOf(address minter) external view returns (uint40);

    /**
     * @notice Returns the last signature timestamp used by `validator` to update collateral for `minter`.
     * @param  minter    The address of the minter.
     * @param  validator The address of the validator.
     * @return The last signature timestamp used.
     */
    function getLastSignatureTimestamp(address minter, address validator) external view returns (uint256);

    /**
     * @notice Returns the EIP-712 digest for updateCollateral method.
     * @param  minter       The address of the minter.
     * @param  collateral   The amount of collateral.
     * @param  retrievalIds The list of outstanding collateral retrieval IDs to resolve.
     * @param  metadataHash The hash of metadata of the collateral update, reserved for future informational use.
     * @param  timestamp    The timestamp of the collateral update.
     */
    function getUpdateCollateralDigest(
        address minter,
        uint256 collateral,
        uint256[] calldata retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp
    ) external view returns (bytes32);

    /// @notice The mint proposal of minters, only 1 active proposal per minter
    function mintProposalOf(
        address minter
    ) external view returns (uint48 mintId, uint40 createdAt, address destination, uint240 amount);

    /// @notice The amount of a pending retrieval request for an active minter.
    function pendingCollateralRetrievalOf(address minter, uint256 retrievalId) external view returns (uint240);

    /// @notice The total amount of pending retrieval requests for an active minter.
    function totalPendingCollateralRetrievalOf(address minter) external view returns (uint240);

    /// @notice The timestamp when minter becomes unfrozen after being frozen by validator.
    function frozenUntilOf(address minter) external view returns (uint40);

    /// @notice Checks if minter was activated after approval by TTG
    function isActiveMinter(address minter) external view returns (bool);

    /// @notice Checks if minter was deactivated after removal by TTG
    function isDeactivatedMinter(address minter) external view returns (bool);

    /// @notice Checks if minter was frozen by validator
    function isFrozenMinter(address minter) external view returns (bool);

    /// @notice Checks if minter was approved by TTG
    function isMinterApproved(address minter) external view returns (bool);

    /// @notice Checks if validator was approved by TTG
    function isValidatorApproved(address validator) external view returns (bool);

    /// @notice The delay between mint proposal creation and its earliest execution.
    function mintDelay() external view returns (uint32);

    /// @notice The time while mint request can still be processed before it is considered expired.
    function mintTTL() external view returns (uint32);

    /// @notice The freeze time for minter.
    function minterFreezeTime() external view returns (uint32);

    /// @notice The allowed activeOwedM to collateral ratio.
    function mintRatio() external view returns (uint32);

    /// @notice The % that defines penalty amount for missed collateral updates or excessive owedM value
    function penaltyRate() external view returns (uint32);

    /// @notice The smart contract that defines the minter rate.
    function rateModel() external view returns (address);

    /// @notice The interval that defines the required frequency of collateral updates.
    function updateCollateralInterval() external view returns (uint32);

    /// @notice The number of signatures required for successful collateral update.
    function updateCollateralValidatorThreshold() external view returns (uint256);

    /// @notice Descaler for variables in basis points. Effectively, 100% in basis points.
    function ONE() external pure returns (uint16);

    /// @notice Mint ratio cap. 650% in basis points.
    function MAX_MINT_RATIO() external pure returns (uint32);

    /// @notice Update collateral interval lower cap in seconds.
    function MIN_UPDATE_COLLATERAL_INTERVAL() external pure returns (uint32);

    /// @notice The EIP-712 typehash for the `updateCollateral` method.
    function UPDATE_COLLATERAL_TYPEHASH() external pure returns (bytes32);
}
