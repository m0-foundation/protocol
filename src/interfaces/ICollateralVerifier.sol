// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

interface ICollateralVerifier {
    error InvalidSignature();
    error InvalidMinter();
    error InvalidValidator();

    function decode(
        address spog,
        bytes calldata data
    ) external view returns (address minter, uint256 collateral, uint256 timestamp);
}
