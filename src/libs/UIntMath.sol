// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

library UIntMath {
    error InvalidUInt24();

    error InvalidUInt48();

    error InvalidUInt64();

    error InvalidUInt128();

    error InvalidUInt184();

    function safe24(uint256 n) internal pure returns (uint24) {
        if (n > type(uint24).max) revert InvalidUInt24();
        return uint24(n);
    }

    function safe48(uint256 n) internal pure returns (uint48) {
        if (n > type(uint48).max) revert InvalidUInt48();
        return uint48(n);
    }

    function safe64(uint256 n) internal pure returns (uint64) {
        if (n > type(uint64).max) revert InvalidUInt64();
        return uint64(n);
    }

    function safe128(uint256 n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert InvalidUInt128();
        return uint128(n);
    }

    function safe184(uint256 n) internal pure returns (uint184) {
        if (n > type(uint184).max) revert InvalidUInt184();
        return uint184(n);
    }
}
