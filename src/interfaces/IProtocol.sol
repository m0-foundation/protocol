// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IStatelessERC712 } from "./IStatelessERC712.sol";

interface IProtocol {
    error NotApprovedMinter();

    error InvalidSignaturesLength();
    error NotEnoughValidSignatures();

    error ExpiredTimestamp();
    error StaleTimestamp();

    error OnlyOneMintRequest();
    error UncollateralizedMint();
    error NoMintRequest();
    error PendingMintRequest();
    error ExpiredMintRequest();
    error Unauthorized();

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);
    event MintRequestedCreated(address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(address indexed minter);
    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 typehash);

    function updateCollateral(
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;

    function proposeMint(uint256 amount, address to) external returns (uint256 mintId);

    function mint(uint256 proposeId) external;

    function cancel(uint256 proposeId) external;

    function freeze(address minter) external;
}
