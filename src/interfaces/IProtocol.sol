// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import { IStatelessERC712 } from "./IStatelessERC712.sol";

interface IProtocol {
    error NotEnoughSignatures();
    error NotMinter();

    error InvalidMinter();
    error InvalidSignature();
    error InvalidSignaturesLength();
    error InvalidValidator();
    error InvalidTimestamp();

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32);

    function updateCollateral(
        address minter,
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;
}
