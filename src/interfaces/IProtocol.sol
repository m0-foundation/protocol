// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

interface IProtocol is IContinuousIndexing {
    /******************************************************************************************************************\
    |                                                      Errors                                                      |
    \******************************************************************************************************************/

    /// @notice Emitted when calling `mintM` with a proposal that was created more than `mintDelay + mintTTL` time ago.
    error ExpiredMintProposal(uint40 deadline);

    /// @notice Emitted when calling `mintM` or `proposeMint` by a minter who was frozen by validator.
    error FrozenMinter();

    /// @notice Emitted when calling `updateCollateral` if validator timestamp is in the future.
    error FutureTimestamp();

    /// @notice Emitted when calling `cancelMint` or `mintM` with invalid `mintId`.
    error InvalidMintProposal();

    /// @notice Emitted when calling `updateCollateral` if `validators` addresses are not ordered in ascending order.
    error InvalidSignatureOrder();

    /// @notice Emitted when calling `deactivateMinter` with an inactive minter.
    error InactiveMinter();

    /// @notice Emitted when calling `activateMinter` with a minter who was previously deactivated.
    error DeactivatedMinter();

    /// @notice Emitted when calling `activateMinter` if minter was not approved by SPOG.
    error NotApprovedMinter();

    /// @notice Emitted when calling `cancelMint` or `freezeMinter` if validator was not approved by SPOG.
    error NotApprovedValidator();

    /// @notice Emitted when calling `updateCollateral` if `validatorThreshold` of signatures was not reached.
    error NotEnoughValidSignatures(uint256 validSignatures, uint256 requiredThreshold);

    /// @notice Emitted when calling `mintM` if `mintDelay` time has not passed yet.
    error PendingMintProposal(uint40 activeTimestamp);

    /// @notice Emitted when calling `proposeRetrieval` if sum of all outstanding retrievals
    ///         Plus new proposed retrieval amount is greater than collateral.
    error RetrievalsExceedCollateral(uint128 totalPendingRetrievals, uint128 collateral);

    /// @notice Emitted when calling `updateCollateral`
    ///         If `validators`, `signatures`, `timestamps` lengths do not match.
    error SignatureArrayLengthsMismatch();

    /// @notice Emitted when calling `updateCollateral` if protocol has more fresh collateral update.
    error StaleCollateralUpdate(uint40 newTimestamp, uint40 lastCollateralUpdate);

    /// @notice Emitted when calling `deactivateMinter` with a minter still approved in SPOG Registrar.
    error StillApprovedMinter();

    /// @notice Emitted when calling `proposeMint`, `mintM`, `proposeRetrieval`
    ///         If minter position becomes undercollateralized.
    error Undercollateralized(uint128 activeOwedM, uint128 maxAllowedOwedM);

    ///  @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    ///  @notice Emitted in constructor if SPOG Registrar is 0x0.
    error ZeroSpogRegistrar();

    ///  @notice Emitted in constructor if SPOG Distribution Vault is set to 0x0 in SPOG Registrar.
    error ZeroSpogVault();

    /******************************************************************************************************************\
    |                                                      Events                                                      |
    \******************************************************************************************************************/

    /**
     * @notice Emitted when a minter's collateral is updated.
     * @param  minter       Address of the minter
     * @param  collateral   The latest amount of collateral
     * @param  retrievalIds The list of outstanding proposeRetrieval requests to close
     * @param  metadataHash The hash of metadata of the collateral update, reserved for future informational use
     * @param  timestamp    The timestamp of the collateral update, minimum of given validators' signatures
     */
    event CollateralUpdated(
        address indexed minter,
        uint128 collateral,
        uint256[] indexed retrievalIds,
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
     * @param  minter        Address of the minter that was deactivated
     * @param  inactiveOwedM Amount of M tokens owed by the minter
     * @param  caller        Address who called the function
     */
    event MinterDeactivated(address indexed minter, uint128 inactiveOwedM, address indexed caller);

    /**
     * @notice Emitted when a minter is frozen.
     * @param  minter      Address of the minter that was frozen
     * @param  frozenUntil Timestamp until the minter is frozen
     */
    event MinterFrozen(address indexed minter, uint40 frozenUntil);

    /**
     * @notice Emitted when mint proposal is created.
     * @param  mintId      The id of mint proposal
     * @param  minter      The address of the minter
     * @param  amount      The amount of M tokens to mint
     * @param  destination The address to mint to
     */
    event MintProposed(uint48 indexed mintId, address indexed minter, uint128 amount, address indexed destination);

    /**
     * @notice Emitted when mint proposal is canceled.
     * @param  mintId    The id of mint proposal
     * @param  canceller The address of validator who cancelled the mint proposal
     */
    event MintCanceled(uint48 indexed mintId, address indexed canceller);

    /**
     * @notice Emitted when mint proposal is executed.
     * @param  mintId The id of executed mint proposal
     */
    event MintExecuted(uint48 indexed mintId);

    /**
     * @notice Emitted when M tokens are burned and minter's owed M balance decreased.
     * @param  minter The address of the minter
     * @param  amount The amount of M tokens to burn
     * @param  payer  The address of the payer
     */
    event BurnExecuted(address indexed minter, uint128 amount, address indexed payer);

    /**
     * @notice Emitted when penalty is imposed on minter.
     * @param  minter The address of the minter
     * @param  amount The amount of penalty charge
     */
    event PenaltyImposed(address indexed minter, uint128 amount);

    /**
     * @notice Emitted when collateral retrieval proposal is created.
     * @param  retrievalId The id of retrieval proposal
     * @param  minter      The address of the minter
     * @param  amount      The amount of collateral to retrieve
     */
    event RetrievalCreated(uint48 indexed retrievalId, address indexed minter, uint128 amount);

    /******************************************************************************************************************\
    |                                          External Interactive Functions                                          |
    \******************************************************************************************************************/

    /**
     * @notice Updates collateral for minters
     * @param  collateral    The amount of collateral
     * @param  retrievalIds  The list of active proposeRetrieval requests to close
     * @param  metadataHash  The hash of metadata of the collateral update, reserved for future informational use
     * @param  validators    The list of validators
     * @param  timestamps    The list of timestamps of validators' signatures
     * @param  signatures    The list of signatures
     * @return minTimestamp  The minimum timestamp of all validators' signatures
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
     * @notice Proposes retrieval of minter's offchain collateral
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
     * @param  mintId The id of outstanding mint proposal for minter
     */
    function mintM(uint256 mintId) external;

    /**
     * @notice Burns M tokens
     * @dev    If amount to burn is greater than minter's owedM including penalties, burn all up to owedM
     * @param  minter The address of the minter to burn M tokens for
     * @param  amount The max amount of M tokens to burn
     */
    function burnM(address minter, uint256 amount) external;

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
     * @dev    MUST revert if `minter` is not recorded as an approved minter in SPOG Registrar.
     * @dev    SHOULD revert if the minter is already active.
     * @param  minter The address of the minter to activate
     */
    function activateMinter(address minter) external;

    /**
     * @notice Deactivates an active minter.
     * @dev    MUST revert if the minter is not an approved minter.
     * @dev    SHOULD revert if the minter is not active.
     * @param  minter The address of the minter to deactivate
     * @return inactiveOwedM The inactive owed M for the deactivated minter
     */
    function deactivateMinter(address minter) external returns (uint128 inactiveOwedM);

    /******************************************************************************************************************\
    |                                           External View/Pure Functions                                           |
    \******************************************************************************************************************/

    /// @notice Descaler for variables in basis points. Effectively, 100% in basis points.
    function ONE() external pure returns (uint16);

    /// @notice The EIP-712 typehash for the `updateCollateral` method.
    function UPDATE_COLLATERAL_TYPEHASH() external pure returns (bytes32);

    /// @notice The address of M token
    function mToken() external view returns (address);

    /// @notice The address of SPOG Registrar contract.
    function spogRegistrar() external view returns (address);

    /// @notice The address of SPOG Vault contract.
    function spogVault() external view returns (address);

    /// @notice The last saved value of Minter rate.
    function minterRate() external view returns (uint32);

    /// @notice The total owed M for all active minters.
    function totalActiveOwedM() external view returns (uint128);

    /// @notice The total owed M for all inactive minters.
    function totalInactiveOwedM() external view returns (uint128);

    /// @notice The total owed M for all minters.
    function totalOwedM() external view returns (uint128);

    /// @notice The difference between total active owed M and M token total supply.
    function excessActiveOwedM() external view returns (uint128);

    /// @notice The active owed M of minter.
    function activeOwedMOf(address minter) external view returns (uint128);

    /// @notice The max allowed active owed M of minter taking into account collateral amount and retrieval proposals.
    function maxAllowedActiveOwedMOf(address minter) external view returns (uint128);

    /// @notice The inactive owed M of deactivated minter.
    function inactiveOwedMOf(address minter) external view returns (uint128);

    /// @notice The collateral of a given minter.
    function collateralOf(address minter) external view returns (uint128);

    /// @notice The timestamp of the last collateral update of minter.
    function collateralUpdateOf(address minter) external view returns (uint40);

    /// @notice The timestamp of the deadline for the next collateral update of minter.
    function collateralUpdateDeadlineOf(address minter) external view returns (uint40);

    /// @notice The length of the last collateral interval for minter in case SPOG changes this parameter.
    function lastCollateralUpdateIntervalOf(address minter) external view returns (uint32);

    /// @notice The timestamp until which minter is already penalized for missed collateral updates.
    function penalizedUntilOf(address minter) external view returns (uint40);

    /// @notice The penalty for missed collateral updates. Penalized once per missed interval.
    function getPenaltyForMissedCollateralUpdates(address minter) external view returns (uint128);

    /// @notice The mint proposal of minters, only 1 active proposal per minter
    function mintProposalOf(
        address minter
    ) external view returns (uint48 mintId, uint40 createdAt, address destination, uint128 amount);

    /// @notice The minter's proposeRetrieval proposal amount
    function pendingCollateralRetrievalOf(address minter, uint256 retrievalId) external view returns (uint128);

    /// @notice The total amount of active proposeRetrieval requests per minter
    function totalPendingCollateralRetrievalsOf(address minter) external view returns (uint128);

    /// @notice The timestamp when minter becomes unfrozen after being frozen by validator.
    function unfrozenTimeOf(address minter) external view returns (uint40);

    /// @notice Checks if minter was activated after approval by SPOG
    function isActiveMinter(address minter) external view returns (bool);

    /// @notice Checks if minter was approved by SPOG
    function isMinterApprovedBySPOG(address minter) external view returns (bool);

    /// @notice Checks if validator was approved by SPOG
    function isValidatorApprovedBySPOG(address validator) external view returns (bool);

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
}
