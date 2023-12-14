// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

// TODO: Can optimize with base-2 scales instead of base-10 (so we can shift instead of divide)

library ContinuousIndexingMath {
    uint32 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice 100% in basis points.
    uint16 internal constant BPS_ONE = 1e4;

    /// @notice The scaling of rates in for exponent math.
    uint56 internal constant EXP_ONE = 1e12;

    function divide(uint256 x, uint256 y) internal pure returns (uint128 z) {
        return uint128((x * EXP_ONE) / y);
    }

    function multiply(uint256 x, uint256 y) internal pure returns (uint128 z) {
        return uint128((x * y) / EXP_ONE);
    }

    /**
     * @notice Helper function to calculate e^rt (continuous compounding formula).
     * @dev    `uint64 yearlyRate` can accommodate 1000% interest per year.
     * @dev    `uint32 time` can accommodate 100 years.
     * @dev    `type(uint64).max * type(uint40).max / SECONDS_PER_YEAR` fits in a `uint72`.
     */
    function getContinuousIndex(uint64 yearlyRate, uint32 time) internal pure returns (uint128 index) {
        return uint128(exponent((uint256(yearlyRate) * uint256(time)) / SECONDS_PER_YEAR));
    }

    /**
     * @notice Helper function to calculate y = e^x using R(4,4) Padé approximation:
     *           e(x) = (1 + z/2 + 3(z^2)/28 + z^3/84 + z^4/1680) / (1 - z/2 + 3(z^2)/28 - z^3/84 + z^4/1680)
     *           See: https://en.wikipedia.org/wiki/Pad%C3%A9_table
     * @dev    Output `y` for a `uint72` input `x` will fit in `uint128`
     */
    function exponent(uint256 x) internal pure returns (uint256 y) {
        uint256 additiveTerms = 84e36 + ((y * y) / 20e12) + (9e12 * (y = x * x));
        uint256 differentTerms = (42e24 * x) + (x * y);

        return ((additiveTerms + differentTerms) * 1e12) / (additiveTerms - differentTerms);
    }

    function convertToBasisPoints(uint64 input) internal pure returns (uint32 output) {
        return uint32((uint256(input) * BPS_ONE) / EXP_ONE);
    }

    function convertFromBasisPoints(uint32 input) internal pure returns (uint64 output) {
        return uint64((uint256(input) * EXP_ONE) / BPS_ONE);
    }
}
