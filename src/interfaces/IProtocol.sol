// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

interface IProtocol is IContinuousIndexing {
    /******************************************************************************************************************\
    |                                                      Errors                                                      |
    \******************************************************************************************************************/

    error NotApprovedMinter();

    error NotApprovedValidator();

    error StillApprovedMinter();

    error FrozenMinter();

    error FutureTimestamp();

    error SignatureArrayLengthsMismatch();

    error InvalidSignatureOrder();

    error NotEnoughValidSignatures();

    error ExpiredCollateralUpdate();

    error StaleCollateralUpdate();

    error Undercollateralized();

    error InvalidMintProposal();

    error PendingMintProposal();

    error ExpiredMintProposal();

    error ZeroSpogRegistrar();

    error ZeroSpogVault();

    error ZeroMToken();

    /******************************************************************************************************************\
    |                                                      Events                                                      |
    \******************************************************************************************************************/

    event CollateralUpdated(address indexed minter, uint256 collateral, bytes32 indexed metadata, uint256 timestamp);

    event MintProposed(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintCanceled(uint256 mintId, address indexed minter, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event MinterDeactivated(address indexed minter, uint256 owedM, address indexed caller);

    event BurnExecuted(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyImposed(address indexed minter, uint256 amount, address indexed caller);

    event RetrievalCreated(uint256 retrievalId, address indexed minter, uint256 amount);

    event RetrievalClosed(uint256 retrievalId, address indexed minter, uint256 amount);

    /// @notice The EIP-712 typehash for the `updateCollateral` method.
    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 typehash);

    /// @notice Descaler for variables in basis points. Effectively, 100% in basis points.
    function ONE() external view returns (uint256 one);

    /// @notice The address of SPOG Registrar contract.
    function spogRegistrar() external view returns (address spogRegistrar);

    /// @notice The address of M token
    function mToken() external view returns (address mToken);

    /// @notice The collateral information of minters
    function collateralOf(
        address minter
    ) external view returns (uint256 collateral, uint256 lastUpdated, uint256 penalizedUntil);

    /// @notice The mint proposal of minters, only 1 request per minter
    function mintProposalOf(
        address minter
    ) external view returns (uint256 mintId, address destination, uint256 amount, uint256 createdAt);

    /// @notice The mint requests of minters, only 1 request per minter
    function unfrozenTimeOf(address minter) external view returns (uint256 timestamp);

    /// @notice The total principal (t0 principal value) of owed M for all active minters
    function totalPrincipalOfActiveOwedM() external view returns (uint256 totalPrincipalOfActiveOwedM);

    /// @notice The total of owed M for all inactive minters
    function totalInactiveOwedM() external view returns (uint256 totalInactiveOwedM);

    /// @notice The principal (t0 principal value) of owed M for each active minters
    function principalOfActiveOwedMOf(address minter) external view returns (uint256 principalOfActiveOwedM);

    /// @notice The owed M for each inactive minters
    function inactiveOwedMOf(address minter) external view returns (uint256 inactiveOwedM);

    /// @notice The total amount of active proposeRetrieval requests per minter
    function totalCollateralPendingRetrievalOf(address minter) external view returns (uint256 collateral);

    /// @notice The minter's proposeRetrieval request amount
    function pendingRetrievalsOf(address minter, uint256 retrievalId) external view returns (uint256 collateral);

    /**
     * @notice Returns the amount of M tokens that minter owes to the protocol
     */
    function activeOwedMOf(address minter) external view returns (uint256 outstandingValue);

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
        bytes32 metadata,
        uint256[] calldata retrieveIds,
        address[] calldata validators,
        uint256[] calldata timestamps,
        bytes[] calldata signatures
    ) external;

    /**
     * @notice Proposes minting of M tokens
     * @param amount The amount of M tokens to mint
     * @param destination The address to mint to
     */
    function proposeMint(uint256 amount, address destination) external returns (uint256 mintId);

    /**
     * @notice Executes minting of M tokens
     * @param mintId The id of outstanding mint request for minter
     */
    function mintM(uint256 mintId) external;

    /**
     * @notice Cancels minting request for minter
     * @param mintId The id of outstanding mint request
     */
    function cancelMint(uint256 mintId) external;

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param minter The address of the minter to cancelMint minting request for
     * @param mintId The id of outstanding mint request
     */
    function cancelMint(address minter, uint256 mintId) external;

    /**
     * @notice Freezes minter
     * @param minter The address of the minter to freezeMinter
     */
    function freezeMinter(address minter) external;

    /**
     * @notice Burns M tokens
     * @param minter The address of the minter to burn M tokens for
     * @param amount The max amount of M tokens to burn
     * @dev If amount to burn is greater than minter's outstandingValue including penalties, burn all outstandingValue
     */
    function burnM(address minter, uint256 amount) external;

    /**
     * @notice Returns the penalty for expired collateral value
     * @param minter The address of the minter to get penalty for
     * @dev Minter is penalized on current outstanding value per every missed interval.
     * @dev Penalized only once per missed interval.
     */
    function getPenaltyForMissedCollateralUpdates(address minter) external view returns (uint256);
}
