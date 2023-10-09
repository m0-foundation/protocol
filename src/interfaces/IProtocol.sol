// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IProtocol {
    error InvalidMinter();
    error InvalidValidator();

    function updateCollateral(
        address minter,
        uint256 amount,
        string memory metadata,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
