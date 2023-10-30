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

    error UncollateralizedMint();
    error NoMintRequest();
    error PendingMintRequest();
    error ExpiredMintRequest();

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);
    event MintRequestedCreated(address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(address indexed minter, address indexed canceller);
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

    function proposeMint(uint256 amount, address to) external;

    function mint() external;

    function cancel(address minter) external;

    function freeze(address minter) external;

    function updateIndices() external;

    function burn(address minter, uint256 amount) external;
}
