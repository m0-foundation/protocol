// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

library UIntMath {
    error InvalidUInt48();

    error InvalidUInt64();

    error InvalidUInt128();

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
}
