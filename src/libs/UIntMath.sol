// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

/**
 * @title Library to perform safe math operations on uint types
 * @author M^ZERO Labs
 */
library UIntMath {
    /// @notice Emitted when a passed value is greater than the maximum value of uint40.
    error InvalidUInt40();

    /// @notice Emitted when a passed value is greater than the maximum value of uint48.
    error InvalidUInt48();

    /// @notice Emitted when a passed value is greater than the maximum value of uint128.
    error InvalidUInt128();

    /**
     * @notice Casts a given uint256 value to a uint40, ensuring that it is less than or equal to the maximum uint40 value.
     * @param  n The value to check.
     * @return The value casted to uint40.
     */
    function safe40(uint256 n) internal pure returns (uint40) {
        if (n > type(uint40).max) revert InvalidUInt40();
        return uint40(n);
    }

    /**
     * @notice Casts a given uint256 value to a uint48, ensuring that it is less than or equal to the maximum uint48 value.
     * @param  n The value to check.
     * @return The value casted to uint48.
     */
    function safe48(uint256 n) internal pure returns (uint48) {
        if (n > type(uint48).max) revert InvalidUInt48();
        return uint48(n);
    }

    /**
     * @notice Casts a given uint256 value to a uint128, ensuring that it is less than or equal to the maximum uint128 value.
     * @param  n The value to check.
     * @return The value casted to uint128.
     */
    function safe128(uint256 n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert InvalidUInt128();
        return uint128(n);
    }

    /**
     * @notice Limits a given uint256 value to the maximum uint32 value.
     * @param  n The value to check.
     * @return The value limited to within uint32 bounds.
     */
    function bound32(uint256 n) internal pure returns (uint32) {
        return uint32(min256(n, uint256(type(uint32).max)));
    }

    /**
     * @notice Compares two uint40 values and returns the larger one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The larger value.
     */
    function max40(uint40 a_, uint40 b_) internal pure returns (uint40) {
        return a_ > b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint256 values and returns the larger one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The larger value.
     */
    function max256(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint32 values and returns the lesser one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The lesser value.
     */
    function min32(uint32 a_, uint32 b_) internal pure returns (uint32) {
        return a_ < b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint40 values and returns the lesser one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The lesser value.
     */
    function min40(uint40 a_, uint40 b_) internal pure returns (uint40) {
        return a_ < b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint128 values and returns the lesser one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The lesser value.
     */
    function min128(uint128 a_, uint128 b_) internal pure returns (uint128) {
        return a_ < b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint256 values and returns the lesser one.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The lesser value.
     */
    function min256(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ < b_ ? a_ : b_;
    }

    /**
     * @notice Compares two uint40 values and returns the lesser one while ignoring zero values.
     * @param  a_  Value to check.
     * @param  b_  Value to check.
     * @return The lesser value.
     */
    function min40IgnoreZero(uint40 a_, uint40 b_) internal pure returns (uint40) {
        return a_ == 0 ? b_ : (b_ == 0 ? a_ : min40(a_, b_));
    }
}
