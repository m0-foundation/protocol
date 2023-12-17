// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "./UIntMath.sol";

// TODO: Consider R(5,5) Padé approximation with some divisions if needed to maintain input range.

/// @notice Arithmetic library with operations for calculating continuous indexing.
/// @author M^ZERO Labs
library ContinuousIndexingMath {
    error DivisionByZero();
    error PowerTooHigh(uint128 power);

    uint32 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice 100% in basis points.
    uint16 internal constant BPS_SCALED_ONE = 1e4;

    /// @notice The scaling of rates in for exponent math.
    uint56 internal constant EXP_SCALED_ONE = 1e12;

    /**
     * @notice Helper function to calculate (`x` * `EXP_SCALED_ONE`) / `y` rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
     */
    function divideDown(uint128 x, uint128 y) internal pure returns (uint128 z) {
        if (y == 0) revert DivisionByZero();

        unchecked {
            return uint128((uint256(x) * EXP_SCALED_ONE) / y);
        }
    }

    /**
     * @notice Helper function to calculate (`x` * `EXP_SCALED_ONE`) / `y` rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
     */
    function divideUp(uint128 x, uint128 y) internal pure returns (uint128 z) {
        if (y == 0) revert DivisionByZero();

        z = uint128(uint256(x) * EXP_SCALED_ONE + y);
        unchecked {
            z -= 1;
        }
        z /= y;
    }

    /**
     * @notice Helper function to calculate (`x` * `y`) / `EXP_SCALED_ONE` rounded down.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
     */
    function multiplyDown(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            return UIntMath.safe128((uint256(x) * y) / EXP_SCALED_ONE);
        }
    }

    /**
     * @notice Helper function to calculate (`x` * `y`) / `EXP_SCALED_ONE` rounded up.
     * @dev    Inspired by USM (https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
     */
    function multiplyUp(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            return UIntMath.safe128((uint256(x) * y + (EXP_SCALED_ONE - 1)) / EXP_SCALED_ONE);
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
            // NOTE: Casting `uint256(yearlyRate) * time` to a `uint72` is safe because the largest value is
            //      `type(uint64).max * type(uint32).max / SECONDS_PER_YEAR`, which is less than `type(uint72).max`.
            return exponent(uint72((uint256(yearlyRate) * time) / SECONDS_PER_YEAR));
        }
    }

    /**
     * @notice Helper function to calculate y = e^x using R(4,4) Padé approximation:
     *           e(x) = (1 + x/2 + 3(x^2)/28 + x^3/84 + x^4/1680) / (1 - x/2 + 3(x^2)/28 - x^3/84 + x^4/1680)
     *           See: https://en.wikipedia.org/wiki/Pad%C3%A9_table
     *         Despite itself being a whole number, `x` represents a real number scaled by `EXP_SCALED_ONE`, thus
     *         allowing for y = e^x where x is a real number.
     * @dev    Output `y` for a `uint72` input `x` will fit in `uint128`
     */
    function exponent(uint72 x) internal pure returns (uint128 y) {
        // NOTE: This can be done unchecked because the largest value is `additiveTerms`, and it's largest possible
        //       value for `x = type(uint72).max` is `287484773207181047759990985259706344810000000000000`, which is
        //       less than `(2 << 167) - 1` (i.e. the max 167-bit number). Then `additiveTerms` is multiplied by 1e12,
        //       which is less than `(2 << 208) - 1` (i.e. the max 208-bit number).
        unchecked {
            // Set `y` to be `x^2` for now.
            y = uint128(x) * x;

            // `additiveTerms` is `(1 + 3(x^2)/28 + x^4/1680)`, but scaled by `84e36`.
            uint256 additiveTerms = 84e36 + (uint256(9e12) * y) + ((uint256(y) * y) / 20e12);

            // `differentTerms` is `(- x/2 - x^3/84)`, but positive (will be subtracted later) and scaled by `84e36`.
            uint256 differentTerms = (42e24 * uint256(x)) + (uint256(x) * y);

            // Result needs to be scaled by `1e12`.
            return uint128(((additiveTerms + differentTerms) * 1e12) / (additiveTerms - differentTerms));
        }
    }

    function convertToBasisPoints(uint64 input) internal pure returns (uint32 output) {
        unchecked {
            return uint32((uint256(input) * BPS_SCALED_ONE) / EXP_SCALED_ONE);
        }
    }

    function convertFromBasisPoints(uint32 input) internal pure returns (uint64 output) {
        unchecked {
            return uint64((uint256(input) * EXP_SCALED_ONE) / BPS_SCALED_ONE);
        }
    }
}
