// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

library UIntMath {
    error InvalidUInt24();

    error InvalidUInt40();

    error InvalidUInt128();

    error InvalidUInt192();

    function safe24(uint256 n) internal pure returns (uint24) {
        if (n > type(uint24).max) revert InvalidUInt24();
        return uint24(n);
    }

    function safe40(uint256 n) internal pure returns (uint40) {
        if (n > type(uint40).max) revert InvalidUInt40();
        return uint40(n);
    }

    function safe128(uint256 n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert InvalidUInt128();
        return uint128(n);
    }

    function safe192(uint256 n) internal pure returns (uint192) {
        if (n > type(uint192).max) revert InvalidUInt192();
        return uint192(n);
    }
}
