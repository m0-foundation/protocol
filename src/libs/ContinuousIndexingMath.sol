// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

// TODO: Can optimize with base-2 scales instead of base-10 (so we can shift instead of divide)

library ContinuousIndexingMath {
    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice The scaling of rates in basis points.
    uint32 internal constant BPS_BASE_SCALE = 1e4;

    /// @notice The scaling of rates in for exponent math.
    uint128 internal constant EXP_BASE_SCALE = 1e18;
    uint256 internal constant EXP_BASE_SCALE_SQUARED = 1e36;
    uint256 internal constant EXP_BASE_SCALE_CUBED = 1e54;
    uint256 internal constant TWO_TIMES_EXP_BASE_SCALE = 2e18;
    uint256 internal constant SIX_TIMES_EXP_BASE_SCALE_SQUARED = 6e36;
    uint256 internal constant TWENTY_FOUR_EXP_BASE_SCALE_CUBED = 24e54;

    function divide(uint256 x, uint256 y) internal pure returns (uint128 z) {
        return uint128((x * EXP_BASE_SCALE) / y);
    }

    function multiply(uint256 x, uint256 y) internal pure returns (uint128 z) {
        return uint128((x * y) / EXP_BASE_SCALE);
    }

    /// @notice Helper function to calculate e^rt (continuous compounding formula).
    function getContinuousIndex(uint256 yearlyRate, uint256 time) internal pure returns (uint128 index) {
        return exponent((yearlyRate * time) / SECONDS_PER_YEAR);
    }

    /// @notice Helper function to calculate y = e^x using fourth degree approximation of Taylor Series:
    ///           e(x) = 1 + x/1! + x^2/2! + x^3/3! + x^4/4!
    function exponent(uint256 x) internal pure returns (uint128 y) {
        uint256 xSquared = x * x;
        uint256 xCubed = xSquared * x;

        return
            uint128(
                EXP_BASE_SCALE + // 1
                    x + // x/1!
                    (xSquared / TWO_TIMES_EXP_BASE_SCALE) + // x^2/2!
                    (xCubed / SIX_TIMES_EXP_BASE_SCALE_SQUARED) + // x^3/3!
                    ((xCubed * x) / TWENTY_FOUR_EXP_BASE_SCALE_CUBED) // x^4/4!
            );
    }

    function convertToBasisPoints(uint128 input) internal pure returns (uint32 output) {
        return uint32((input * BPS_BASE_SCALE) / EXP_BASE_SCALE);
    }

    function convertFromBasisPoints(uint32 input) internal pure returns (uint128 output) {
        return (input * EXP_BASE_SCALE) / BPS_BASE_SCALE;
    }
}
