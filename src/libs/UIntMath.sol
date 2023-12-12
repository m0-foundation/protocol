// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

library UIntMath {
    error InvalidUInt40();

    error InvalidUInt128();

    function safe40(uint256 n) internal pure returns (uint40) {
        if (n > type(uint40).max) revert InvalidUInt40();
        return uint40(n);
    }

    function safe128(uint256 n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert InvalidUInt128();
        return uint128(n);
    }

    function bound32(uint256 n) internal pure returns (uint32) {
        return uint32(min256(n, uint256(type(uint32).max)));
    }

    function max40(uint40 a_, uint40 b_) internal pure returns (uint40 max_) {
        return a_ > b_ ? a_ : b_;
    }

    function min40(uint40 a_, uint40 b_) internal pure returns (uint40 min_) {
        return a_ < b_ ? a_ : b_;
    }

    function min128(uint128 a_, uint128 b_) internal pure returns (uint128 min_) {
        return a_ < b_ ? a_ : b_;
    }

    function min256(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ < b_ ? a_ : b_;
    }

    function min40IgnoreZero(uint40 a_, uint40 b_) internal pure returns (uint40 min_) {
        return a_ == 0 ? b_ : (b_ == 0 ? a_ : min40(a_, b_));
    }
}
