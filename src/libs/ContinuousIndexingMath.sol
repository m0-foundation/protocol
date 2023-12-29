// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { wadExp } from "../../lib/solmate/src/utils/SignedWadMath.sol";

import { UIntMath } from "./UIntMath.sol";

/**
 * @title Arithmetic library with operations for calculating continuous indexing.
 * @author M^ZERO Labs
 */
library ContinuousIndexingMath {
    /// @notice Emitted when a division by zero occurs.
    error DivisionByZero();

    /// @notice The number of seconds in a year.
    uint32 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice 100% in basis points.
    uint16 internal constant BPS_SCALED_ONE = 1e4;

    /// @notice The scaling of rates in for exponent math.
    uint64 internal constant EXP_SCALED_ONE = 1e18;

    /**
     * @notice Helper function to calculate (`x` * `EXP_SCALED_ONE`) / `y`, rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function divideDown(uint128 x, uint128 y) internal pure returns (uint128 z) {
        if (y == 0) revert DivisionByZero();

        unchecked {
            return uint128((uint256(x) * EXP_SCALED_ONE) / y);
        }
    }

    /**
     * @notice Helper function to calculate (`x` * `EXP_SCALED_ONE`) / `y`, rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function divideUp(uint128 x, uint128 y) internal pure returns (uint128 z) {
        if (y == 0) revert DivisionByZero();

        unchecked {
            return uint128(((uint256(x) * EXP_SCALED_ONE) + y - 1) / y);
        }
    }

    /**
     * @notice Helper function to calculate (`x` * `y`) / `EXP_SCALED_ONE`, rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyDown(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            return UIntMath.safe128((uint256(x) * y) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate (`x` * `y`) / `EXP_SCALED_ONE`, rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyUp(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            return UIntMath.safe128(((uint256(x) * y) + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate e^rt (continuous compounding formula).
     * @dev    `uint64 yearlyRate` can accommodate 1000% interest per year.
     * @dev    `uint32 time` can accommodate 100 years.
     * @dev    `type(uint64).max * type(uint32).max / SECONDS_PER_YEAR` fits in a `uint72`.
     */
    function getContinuousIndex(uint64 yearlyRate, uint32 time) internal pure returns (uint128 index) {
        unchecked {
            // NOTE: Casting `uint256(yearlyRate) * time` to a `int256` is safe because the largest value is
            //      `type(uint64).max * type(uint32).max / SECONDS_PER_YEAR`, which is less than `type(int256).max`.
            return uint128(uint256(wadExp(int256((uint256(yearlyRate) * time) / SECONDS_PER_YEAR))));
        }
    }

    /**
     * @notice Helper function to convert 12-decimal representation to basis points.
     * @param  input The input in 12-decimal representation.
     * @return The output in basis points.
     */
    function convertToBasisPoints(uint64 input) internal pure returns (uint32) {
        unchecked {
            return uint32((uint256(input) * BPS_SCALED_ONE) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to convert basis points to 12-decimal representation.
     * @param  input The input in basis points.
     * @return The output in 12-decimal representation.
     */
    function convertFromBasisPoints(uint32 input) internal pure returns (uint64) {
        unchecked {
            return uint64((uint256(input) * EXP_SCALED_ONE) / BPS_SCALED_ONE);
        }
    }
}
