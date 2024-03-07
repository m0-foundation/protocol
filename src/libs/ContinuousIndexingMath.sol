// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

/**
 * @title  Arithmetic library with operations for calculating continuous indexing.
 * @author M^0 Labs
 */
library ContinuousIndexingMath {
    /* ============ Variables ============ */

    /// @notice The number of seconds in a year.
    uint32 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice 100% in basis points.
    uint16 internal constant BPS_SCALED_ONE = 1e4;

    /// @notice The scaling of rates in for exponent math.
    uint56 internal constant EXP_SCALED_ONE = 1e12;

    /* ============ Custom Errors ============ */

    /// @notice Emitted when a division by zero occurs.
    error DivisionByZero();

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Helper function to calculate `(x * EXP_SCALED_ONE) / index`, rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function divideDown(uint240 x, uint128 index) internal pure returns (uint112 z) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            // NOTE: While `uint256(x) * EXP_SCALED_ONE` can technically overflow, these divide/multiply functions are
            //       only used for the purpose of principal/present amount calculations for continuous indexing, and
            //       so for an `x` to be large enough to overflow this, it would have to be a possible result of
            //       `multiplyDown` or `multiplyUp`, which would already satisfy
            //       `uint256(x) * EXP_SCALED_ONE < type(uint240).max`.
            return UIntMath.safe112((uint256(x) * EXP_SCALED_ONE) / index);
        }
    }

    /**
     * @notice Helper function to calculate `(x * EXP_SCALED_ONE) / index`, rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function divideUp(uint240 x, uint128 index) internal pure returns (uint112 z) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            // NOTE: While `uint256(x) * EXP_SCALED_ONE` can technically overflow, these divide/multiply functions are
            //       only used for the purpose of principal/present amount calculations for continuous indexing, and
            //       so for an `x` to be large enough to overflow this, it would have to be a possible result of
            //       `multiplyDown` or `multiplyUp`, which would already satisfy
            //       `uint256(x) * EXP_SCALED_ONE < type(uint240).max`.
            return UIntMath.safe112(((uint256(x) * EXP_SCALED_ONE) + index - 1) / index);
        }
    }

    /**
     * @notice Helper function to calculate `(x * index) / EXP_SCALED_ONE`, rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyDown(uint112 x, uint128 index) internal pure returns (uint240 z) {
        unchecked {
            return uint240((uint256(x) * index) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate `(x * index) / EXP_SCALED_ONE`, rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyUp(uint112 x, uint128 index) internal pure returns (uint240 z) {
        unchecked {
            return uint240(((uint256(x) * index) + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate `(index * deltaIndex) / EXP_SCALED_ONE`, rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyIndicesDown(uint128 index, uint48 deltaIndex) internal pure returns (uint144 z) {
        unchecked {
            return uint144((uint256(index) * deltaIndex) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate `(index * deltaIndex) / EXP_SCALED_ONE`, rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol)
     */
    function multiplyIndicesUp(uint128 index, uint48 deltaIndex) internal pure returns (uint144 z) {
        unchecked {
            return uint144((uint256(index) * deltaIndex + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate e^rt (continuous compounding formula).
     * @dev    `uint64 yearlyRate` can accommodate 1000% interest per year.
     * @dev    `uint32 time` can accommodate 100 years.
     * @dev    `type(uint64).max * type(uint32).max / SECONDS_PER_YEAR` fits in a `uint72`.
     */
    function getContinuousIndex(uint64 yearlyRate, uint32 time) internal pure returns (uint48 index) {
        unchecked {
            // NOTE: Casting `uint256(yearlyRate) * time` to a `uint72` is safe because the largest value is
            //      `type(uint64).max * type(uint32).max / SECONDS_PER_YEAR`, which is less than `type(uint72).max`.
            return exponent(uint72((uint256(yearlyRate) * time) / SECONDS_PER_YEAR));
        }
    }

    /**
     * @notice Helper function to calculate y = e^x using R(4,4) Padé approximation:
     *           e(x) = (1 + x/2 + 3(x^2)/28 + x^3/84 + x^4/1680) / (1 - x/2 + 3(x^2)/28 - x^3/84 + x^4/1680)
     *           See: https://en.wikipedia.org/wiki/Pad%C3%A9_table
     *           See: https://www.wolframalpha.com/input?i=PadeApproximant%5Bexp%5Bx%5D%2C%7Bx%2C0%2C%7B4%2C+4%7D%7D%5D
     *         Despite itself being a whole number, `x` represents a real number scaled by `EXP_SCALED_ONE`, thus
     *         allowing for y = e^x where x is a real number.
     * @dev    Output `y` for a `uint72` input `x` will fit in `uint48`
     */
    function exponent(uint72 x) internal pure returns (uint48 y) {
        // NOTE: This can be done unchecked even for `x = type(uint72).max`.
        //       Verify by removing `unchecked` and running `test_exponent()`.
        unchecked {
            uint256 x2 = uint256(x) * x;

            // `additiveTerms` is `(1 + 3(x^2)/28 + x^4/1680)`, and scaled by `84e27`.
            // NOTE: `84e27` the cleanest and largest scalar, given the various intermediate overflow possibilities.
            // NOTE: The resulting `(x2 * x2) / 20e21` term has been split up in order to avoid overflow of `x2 * x2`.
            uint256 additiveTerms = 84e27 + (9e3 * x2) + ((x2 / 2e11) * (x2 / 1e11));

            // `differentTerms` is `(- x/2 - x^3/84)`, but positive (will be subtracted later), and scaled by `84e27`.
            uint256 differentTerms = uint256(x) * (42e15 + (x2 / 1e9));

            // Result needs to be scaled by `1e12`.
            // NOTE: Can cast to `uint48` because contents can never be larger than `type(uint48).max` for any `x`.
            //       Max `y` is ~200e12, before falling off. See links above for reference.
            return uint48(((additiveTerms + differentTerms) * 1e12) / (additiveTerms - differentTerms));
        }
    }

    /**
     * @notice Helper function to convert 12-decimal representation to basis points.
     * @param  input The input in 12-decimal representation.
     * @return The output in basis points.
     */
    function convertToBasisPoints(uint64 input) internal pure returns (uint40) {
        unchecked {
            return uint40((uint256(input) * BPS_SCALED_ONE) / EXP_SCALED_ONE);
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
