// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

interface IProtocol is IContinuousIndexing {
    /******************************************************************************************************************\
    |                                                      Errors                                                      |
    \******************************************************************************************************************/

    /// @notice Emitted when calling `activeMinter` with an already active minter.
    error AlreadyActiveMinter();

    error ExpiredMintProposal(uint256 deadline);

    error FrozenMinter();

    error FutureTimestamp();

    error InvalidMintProposal();

    error InvalidSignatureOrder();

    /// @notice Emitted when calling `deactivateMinter` with an inactive minter.
    error InactiveMinter();

    error NotApprovedMinter();

    error NotApprovedValidator();

    error NotEnoughValidSignatures(uint256 validSignatures, uint256 requiredThreshold);

    error PendingMintProposal(uint256 activeTimestamp);

    error SignatureArrayLengthsMismatch();

    error StaleCollateralUpdate(uint256 newTimestamp, uint256 lastCollateralUpdate);

    /// @notice Emitted when calling `deactivateMinter` with a minter still approved in SPOG Registrar.
    error StillApprovedMinter();

    error Undercollateralized(uint256 activeOwedM, uint256 maxAllowedOwedM);

    error ZeroMToken();

    error ZeroSpogRegistrar();

    error ZeroSpogVault();

    /******************************************************************************************************************\
    |                                                      Events                                                      |
    \******************************************************************************************************************/

    event BurnExecuted(address indexed minter, uint256 amount, address indexed payer);

    event CollateralUpdated(
        address indexed minter,
        uint256 collateral,
        uint256[] indexed retrievalIds,
        bytes32 indexed metadata,
        uint256 timestamp
    );

    event MintCanceled(uint256 indexed mintId, address indexed canceller);

    /**
     * @notice Emitted when a minter is activated.
     * @param minter Address of the minter that was activated
     * @param caller Address who called the function
     */
    event MinterActivated(address indexed minter, address indexed caller);

    /**
     * @notice Emitted when a minter is deactivated.
     * @param minter Address of the minter that was deactivated
     * @param owedM Amount of M tokens owed by the minter
     * @param caller Address who called the function
     */
    event MinterDeactivated(address indexed minter, uint256 owedM, address indexed caller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil, address indexed validator);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event MinterRemoved(address indexed minter, uint256 inactiveOwedM);

    event MintExecuted(uint256 indexed mintId);

    event MintProposed(uint256 indexed mintId, address indexed minter, uint256 amount, address indexed destination);

    event MintRequestCanceled(uint256 indexed mintId, address indexed caller);

    event MintRequestExecuted(uint256 indexed mintId);

    event PenaltyAccrued(address indexed minter, uint256 amount);

    event PenaltyImposed(address indexed minter, uint256 amount);

    event RetrievalCreated(uint256 indexed retrievalId, address indexed minter, uint256 amount);

    /******************************************************************************************************************\
    |                                          External Interactive Functions                                          |
    \******************************************************************************************************************/

    /**
     * @notice Activate an approved minter.
     * @dev MUST revert if `minter` is not recorded as an approved minter in SPOG Registrar.
     * @dev SHOULD revert if the minter is already active.
     * @param minter The address of the minter to activate
     */
    function activateMinter(address minter) external;

    /**
     * @notice Burns M tokens
     * @param minter The address of the minter to burn M tokens for
     * @param amount The max amount of M tokens to burn
     * @dev If amount to burn is greater than minter's outstandingValue including penalties, burn all outstandingValue
     */
    function burnM(address minter, uint256 amount) external;

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param minter The address of the minter to cancelMint minting request for
     * @param mintId The id of outstanding mint request
     */
    function cancelMint(address minter, uint256 mintId) external;

    /**
     * @notice Deactivates an active minter.
     * @dev MUST revert if the minter is not an approved minter.
     * @dev SHOULD revert if the minter is not active.
     * @param minter The address of the minter to deactivate
     * @return inactiveOwedM The inactive owed M for the deactivated minter
     */
    function deactivateMinter(address minter) external returns (uint256 inactiveOwedM);

    /**
     * @notice Freezes minter
     * @param minter The address of the minter to freeze
     */
    function freezeMinter(address minter) external returns (uint256 frozenUntil_);

    /**
     * @notice Executes minting of M tokens
     * @param mintId The id of outstanding mint request for minter
     */
    function mintM(uint256 mintId) external;

    /**
     * @notice Proposes minting of M tokens
     * @param amount The amount of M tokens to mint
     * @param destination The address to mint to
     */
    function proposeMint(uint256 amount, address destination) external returns (uint256 mintId);

    function proposeRetrieval(uint256 collateral) external returns (uint256 retrievalId);

    /**
     * @notice Updates collateral for minters
     * @param collateral The amount of collateral
     * @param metadata The metadata of the update, reserved for future informational use
     * @param retrieveIds The list of active proposeRetrieval requests to close
     * @param timestamps The list of timestamps of validators' signatures
     * @param validators The list of validators
     * @param signatures The list of signatures
     */
    function updateCollateral(
        uint256 collateral,
        uint256[] calldata retrieveIds,
        bytes32 metadata,
        address[] calldata validators,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external returns (uint256 minTimestamp_);

    /******************************************************************************************************************\
    |                                           External View/Pure Functions                                           |
    \******************************************************************************************************************/

    /// @notice Descaler for variables in basis points. Effectively, 100% in basis points.
    function ONE() external pure returns (uint256 one);

    /// @notice The EIP-712 typehash for the `updateCollateral` method.
    function UPDATE_COLLATERAL_TYPEHASH() external pure returns (bytes32 typehash);

    /**
     * @notice The active owed M for a given active minter.
     * @param minter Address of the minter to get active owed M for
     * @return activeOwedM The active owed M for the given active minter
     */
    function activeOwedMOf(address minter) external view returns (uint256 activeOwedM);

    /// @notice The collateral of a given minter.
    function collateralOf(address minter) external view returns (uint256 collateral);

    function collateralUpdateDeadlineOf(address minter) external view returns (uint256 lastUpdate);

    function excessActiveOwedM() external view returns (uint256 getExcessOwedM);

    function getMaxAllowedOwedM(address minter_) external view returns (uint256 maxAllowedOwedM);

    /**
     * @notice Returns the penalty for expired collateral value.
     * @dev Minter is penalized on current outstanding value per every missed interval.
     * @dev Penalized only once per missed interval.
     * @param minter Address of the minter to get penalty for
     * @return penalty The penalty for the given minter
     */
    function getPenaltyForMissedCollateralUpdates(address minter) external view returns (uint256 penalty);

    /**
     * @notice Returns whether the given minter is active or not.
     * @param minter Address of the minter to check
     * @return isActive True for an active minter, false otherwise
     */
    function isActiveMinter(address minter) external view returns (bool isActive);

    function isMinterApprovedByRegistrar(address minter_) external view returns (bool isApproved);

    function isValidatorApprovedByRegistrar(address validator_) external view returns (bool isApproved);

    /// @notice The inactive owed M for a given active minter
    function inactiveOwedMOf(address minter) external view returns (uint256 inactiveOwedM);

    function latestMinterRate() external view returns (uint256 latestMinterRate);

    function lastUpdateIntervalOf(address minter) external view returns (uint256 lastUpdateInterval);

    function lastUpdateOf(address minter) external view returns (uint256 lastUpdate);

    function mintDelay() external view returns (uint256 mintDelay);

    function minterFreezeTime() external view returns (uint256 minterFreezeTime);

    function minterRate() external view returns (uint256 minterRate);

    /// @notice The mint proposal of minters, only 1 request per minter
    function mintProposalOf(
        address minter
    ) external view returns (uint256 mintId, address destination, uint256 amount, uint256 createdAt);

    function mintRatio() external view returns (uint256 mintRatio);

    function mintTTL() external view returns (uint256 mintTTL);

    /// @notice The address of M token
    function mToken() external view returns (address mToken);

    function penalizedUntilOf(address minter) external view returns (uint256 penalizedUntil);

    function penaltyRate() external view returns (uint256 penaltyRate);

    /// @notice The minter's proposeRetrieval request amount
    function pendingRetrievalsOf(address minter, uint256 retrievalId) external view returns (uint256 collateral);

    function rateModel() external view returns (address rateModel);

    /// @notice The address of SPOG Registrar contract.
    function spogRegistrar() external view returns (address spogRegistrar);

    /// @notice The address of SPOG Vault contract.
    function spogVault() external view returns (address spogVault);

    /// @notice The total owed M for all active minters
    function totalActiveOwedM() external view returns (uint256 totalActiveOwedM);

    /// @notice The total amount of active proposeRetrieval requests per minter
    function totalCollateralPendingRetrievalOf(address minter) external view returns (uint256 collateral);

    /// @notice The total owed M for all inactive minters
    function totalInactiveOwedM() external view returns (uint256 totalInactiveOwedM);

    /// @notice The total owed M for all minters
    function totalOwedM() external view returns (uint256 totalOwedM);

    /// @notice The mint requests of minters, only 1 request per minter
    function unfrozenTimeOf(address minter) external view returns (uint256 timestamp);

    function updateCollateralInterval() external view returns (uint256 updateCollateralInterval);

    function validatorThreshold() external view returns (uint256 threshold);
}
