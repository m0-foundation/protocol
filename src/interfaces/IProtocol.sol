// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IContinuousInterestIndexing } from "./IContinuousInterestIndexing.sol";

interface IProtocol is IContinuousInterestIndexing {
    /******************************************************************************************************************\
    |                                                      Errors                                                      |
    \******************************************************************************************************************/

    error NotApprovedMinter();

    error NotApprovedValidator();

    error StillApprovedMinter();

    error FrozenMinter();

    error InvalidSignaturesLength();

    error NotEnoughValidSignatures();

    error ExpiredTimestamp();

    error StaleTimestamp();

    error UndercollateralizedMint();

    error InvalidMintRequest();

    error PendingMintRequest();

    error ExpiredMintRequest();

    error ZeroSpogRegistrar();

    error ZeroSpogVault();

    error ZeroMToken();

    /******************************************************************************************************************\
    |                                                      Events                                                      |
    \******************************************************************************************************************/

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    event MintRequestedCreated(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintRequestExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintRequestCanceled(uint256 mintId, address indexed minter, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event MinterRemoved(address indexed minter, uint256 outstandingValue, address indexed remover);

    event Burn(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyAccrued(address indexed minter, uint256 amount, address indexed caller);

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
    ) external view returns (uint256 amount, uint256 lastUpdated, uint256 penalizedUntil);

    /// @notice The mint requests of minters, only 1 request per minter
    function mintRequestOf(
        address minter
    ) external view returns (uint256 mintId, address to, uint256 amount, uint256 createdAt);

    /// @notice The mint requests of minters, only 1 request per minter
    function unfrozenTimeOf(address minter) external view returns (uint256 timestamp);

    /// @notice The total normalized principal (t0 principal value) for all minters
    function totalNormalizedPrincipal() external view returns (uint256 totalNormalizedPrincipal);

    /// @notice The total outstanding value for all removed minters
    function totalRemovedOutstandingValue() external view returns (uint256 totalRemovedOutstandingValue);

    /// @notice The normalized principal (t0 principal value) for each minter
    function normalizedPrincipalOf(address minter) external view returns (uint256 amount);

    /// @notice The outstanding value of removed minter
    function removedOutstandingValueOf(address minter) external view returns (uint256 removedOutstandingValueOf);

    /**
     * @notice Returns the amount of M tokens that minter owes to the protocol
     */
    function outstandingValueOf(address minter) external view returns (uint256 outstandingValue);

    /**
     * @notice Updates collateral for minters
     * @param amount The amount of collateral
     * @param timestamp The timestamp of the update
     * @param metadata The metadata of the update, reserved for future informational use
     * @param validators The list of validators
     * @param signatures The list of signatures
     */
    function updateCollateral(
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;

    /**
     * @notice Proposes minting of M tokens
     * @param amount The amount of M tokens to mint
     * @param to The address to mint to
     */
    function proposeMint(uint256 amount, address to) external returns (uint256 mintId);

    /**
     * @notice Executes minting of M tokens
     * @param mintId The id of outstanding mint request for minter
     */
    function mint(uint256 mintId) external;

    /**
     * @notice Cancels minting request for minter
     * @param mintId The id of outstanding mint request
     */
    function cancel(uint256 mintId) external;

    /**
     * @notice Cancels minting request for selected minter by validator
     * @param minter The address of the minter to cancel minting request for
     * @param mintId The id of outstanding mint request
     */
    function cancel(address minter, uint256 mintId) external;

    /**
     * @notice Freezes minter
     * @param minter The address of the minter to freeze
     */
    function freeze(address minter) external;

    /**
     * @notice Burns M tokens
     * @param minter The address of the minter to burn M tokens for
     * @param amount The max amount of M tokens to burn
     * @dev If amount to burn is greater than minter's outstandingValue including penalties, burn all outstandingValue
     */
    function burn(address minter, uint256 amount) external;

    /**
     * @notice Returns the penalty for expired collateral value
     * @param minter The address of the minter to get penalty for
     * @dev Minter is penalized on current outstanding value per every missed interval.
     * @dev Penalized only once per missed interval.
     */
    function getUnaccruedPenaltyForExpiredCollateralValue(address minter) external view returns (uint256);
}
