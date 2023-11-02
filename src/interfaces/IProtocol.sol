// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IProtocol {
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

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    event MintRequestedCreated(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(uint256 mintId, address indexed minter, address indexed canceller);
    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event Burn(address indexed minter, address indexed payer, uint256 amount);

    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 typehash);

    function updateCollateral(
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;

    function proposeMint(uint256 amount, address to) external returns (uint256 mintId);

    function mint(uint256 mintId) external;

    function cancel(uint256 mintId) external;

    function cancel(address minter, uint256 mintId) external;

    function freeze(address minter) external;

    function updateIndices() external;

    function burn(address minter, uint256 amount) external;
}
