// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IStatelessERC712 } from "./IStatelessERC712.sol";

interface IProtocol {
    error NotApprovedMinter();

    error InvalidSignaturesLength();
    error NotEnoughValidSignatures();

    error ExpiredTimestamp();
    error StaleTimestamp();

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    function UPDATE_COLLATERAL_TYPEHASH() external view returns (bytes32 typehash);

    function updateCollateral(
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;
}
