// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface IProtocol {
    error NotEnoughSignatures();
    error NotMinter();

    error InvalidMinter();
    error InvalidSignature();
    error InvalidSignaturesLength();
    error InvalidValidator();
    error InvalidTimestamp();

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    function updateCollateral(
        address minter,
        uint256 amount,
        uint256 timestamp,
        string memory metadata,
        address[] calldata validators,
        bytes[] calldata signatures
    ) external;
}
