// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IProtocol {
    /******************************************************************************************************************\
    |                                                      Errors                                                      |
    \******************************************************************************************************************/

    error NotApprovedMinter();

    error NotApprovedValidator();

    error FrozenMinter();

    error InvalidSignaturesLength();

    error NotEnoughValidSignatures();

    error ExpiredTimestamp();

    error StaleTimestamp();

    error UndercollateralizedMint();

    error InvalidMintRequest();

    error PendingMintRequest();

    error ExpiredMintRequest();

    /******************************************************************************************************************\
    |                                                      Events                                                      |
    \******************************************************************************************************************/

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    event MintRequestedCreated(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintRequestExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);

    event MintRequestCanceled(uint256 mintId, address indexed minter, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event Burn(address indexed minter, address indexed payer, uint256 amount);

    /// @notice The EIP-712 typehash for the `updateCollateral` method.
    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 typehash);

    /// @notice Descaler for variables in basis points. Effectively, 100% in basis points.
    function ONE() external view returns (uint256 one);

    /// @notice The address of SPOG Registrar contract.
    function spogRegistrar() external view returns (address spogRegistrar);

    /// @notice The address of M token
    function mToken() external view returns (address mToken);

    /// @notice The collateral information of minters
    function collateralOf(address minter) external view returns (uint256 amount, uint256 lastUpdated);

    /// @notice The mint requests of minters, only 1 request per minter
    function mintRequestOf(
        address minter
    ) external view returns (uint256 mintId, address to, uint256 amount, uint256 createdAt);

    /// @notice The mint requests of minters, only 1 request per minter
    function frozenUntilOf(address minter) external view returns (uint256 timestamp);

    /// @notice The total normalized principal (t0 principal value) for all minters
    function totalNormalizedPrincipal() external view returns (uint256 totalNormalizedPrincipal);

    /// @notice The normalized principal (t0 principal value) for each minter
    function normalizedPrincipalOf(address minter) external view returns (uint256 amount);

    /// @notice The current M index for the protocol tracked for the entire market
    function mIndex() external view returns (uint256 mIndex);

    /// @notice The timestamp of the last time the M index was updated
    function lastAccrualTime() external view returns (uint256 lastAccrualTime);

    /**
     * @notice Returns the amount of M tokens that minter owes to the protocol
     */
    function debtOf(address minter_) external view returns (uint256 debt);

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
     * @notice Updates indices
     */
    function updateIndices() external;

    /**
     * @notice Burns M tokens
     * @param minter The address of the minter to burn M tokens for
     * @param amount The max amount of M tokens to burn
     * @dev If amount to burn is greater than minter's debt, burn all debt
     */
    function burn(address minter, uint256 amount) external;
}
