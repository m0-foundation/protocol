// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

contract ContinuousIndexingMathTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = ContinuousIndexingMath.EXP_SCALED_ONE;

    function test_divideDown() external {
        // Set 1a
        assertEq(ContinuousIndexingMath.divideDown(0, 1), 0);
        assertEq(ContinuousIndexingMath.divideDown(1, 1), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(2, 1), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(3, 1), 3 * _EXP_SCALED_ONE);

        // Set 1b
        assertEq(ContinuousIndexingMath.divideDown(1, 1), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(1, 2), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideDown(1, 3), _EXP_SCALED_ONE / 3); // Different than divideUp

        // Set 2a
        assertEq(ContinuousIndexingMath.divideDown(0, 10), 0);
        assertEq(ContinuousIndexingMath.divideDown(5, 10), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideDown(10, 10), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(15, 10), _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideDown(20, 10), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(25, 10), 2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);

        // Set 2b
        assertEq(ContinuousIndexingMath.divideDown(10, 5), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(10, 10), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideDown(10, 15), (2 * _EXP_SCALED_ONE) / 3); // Different than divideUp
        assertEq(ContinuousIndexingMath.divideDown(10, 20), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideDown(10, 25), (2 * _EXP_SCALED_ONE) / 5);

        // Set 3
        assertEq(ContinuousIndexingMath.divideDown(1, _EXP_SCALED_ONE + 1), 0); // Different than divideUp
        assertEq(ContinuousIndexingMath.divideDown(1, _EXP_SCALED_ONE), 1);
        assertEq(ContinuousIndexingMath.divideDown(1, _EXP_SCALED_ONE - 1), 1); // Different than divideUp
        assertEq(ContinuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2) + 1), 1); // Different than divideUp
        assertEq(ContinuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2)), 2);
        assertEq(ContinuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2) - 1), 2); // Different than divideUp
    }

    function test_divideUp() external {
        // Set 1a
        assertEq(ContinuousIndexingMath.divideUp(0, 1), 0);
        assertEq(ContinuousIndexingMath.divideUp(1, 1), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(2, 1), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(3, 1), 3 * _EXP_SCALED_ONE);

        // Set 1b
        assertEq(ContinuousIndexingMath.divideUp(1, 1), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(1, 2), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideUp(1, 3), _EXP_SCALED_ONE / 3 + 1); // Different than divideDown

        // Set 2a
        assertEq(ContinuousIndexingMath.divideUp(0, 10), 0);
        assertEq(ContinuousIndexingMath.divideUp(5, 10), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideUp(10, 10), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(15, 10), _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideUp(20, 10), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(25, 10), 2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);

        // Set 2b
        assertEq(ContinuousIndexingMath.divideUp(10, 5), 2 * _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(10, 10), _EXP_SCALED_ONE);
        assertEq(ContinuousIndexingMath.divideUp(10, 15), (2 * _EXP_SCALED_ONE) / 3 + 1); // Different than divideDown
        assertEq(ContinuousIndexingMath.divideUp(10, 20), _EXP_SCALED_ONE / 2);
        assertEq(ContinuousIndexingMath.divideUp(10, 25), (2 * _EXP_SCALED_ONE) / 5);

        // Set 3
        assertEq(ContinuousIndexingMath.divideUp(1, _EXP_SCALED_ONE + 1), 1); // Different than divideDown
        assertEq(ContinuousIndexingMath.divideUp(1, _EXP_SCALED_ONE), 1);
        assertEq(ContinuousIndexingMath.divideUp(1, _EXP_SCALED_ONE - 1), 2); // Different than divideDown
        assertEq(ContinuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2) + 1), 2); // Different than divideDown
        assertEq(ContinuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2)), 2);
        assertEq(ContinuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2) - 1), 3); // Different than divideDown
    }

    function test_multiplyDown() external {
        // Set 1a
        assertEq(ContinuousIndexingMath.multiplyDown(0, 1), 0);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 1), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 1), 2);
        assertEq(ContinuousIndexingMath.multiplyDown(3 * _EXP_SCALED_ONE, 1), 3);

        // Set 1b
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 1), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 2), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 3, 3), 0);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 3 + 1, 3), 1);

        // Set 2a
        assertEq(ContinuousIndexingMath.multiplyDown(0, 10), 0);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 10), 5);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 10), 10);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 15);
        assertEq(ContinuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 10), 20);
        assertEq(ContinuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 25);

        // Set 2b
        assertEq(ContinuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 5), 10);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 10), 10);
        assertEq(ContinuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 3, 15), 9);
        assertEq(ContinuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 3 + 1, 15), 10);
        assertEq(ContinuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 20), 10);
        assertEq(ContinuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 5, 25), 10);

        // Set 3
        assertEq(ContinuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE + 1), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE - 1), 0);
        assertEq(ContinuousIndexingMath.multiplyDown(1, (_EXP_SCALED_ONE / 2) + 1), 0);
        assertEq(ContinuousIndexingMath.multiplyDown(2, (_EXP_SCALED_ONE / 2)), 1);
        assertEq(ContinuousIndexingMath.multiplyDown(2, (_EXP_SCALED_ONE / 2) - 1), 0);
    }

    function test_multiplyUp() external {
        // Set 1a
        assertEq(ContinuousIndexingMath.multiplyUp(0, 1), 0);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 1), 1);
        assertEq(ContinuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 1), 2);
        assertEq(ContinuousIndexingMath.multiplyUp(3 * _EXP_SCALED_ONE, 1), 3);

        // Set 1b
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 1), 1);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 2), 1);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 3, 3), 1); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 3 + 1, 3), 2); // Different than multiplyDown

        // Set 2a
        assertEq(ContinuousIndexingMath.multiplyUp(0, 10), 0);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 10), 5);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 10), 10);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 15);
        assertEq(ContinuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 10), 20);
        assertEq(ContinuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 25);

        // Set 2b
        assertEq(ContinuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 5), 10);
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 10), 10);
        assertEq(ContinuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 3, 15), 10); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 3 + 1, 15), 11); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 20), 10);
        assertEq(ContinuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 5, 25), 10);

        // Set 3
        assertEq(ContinuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE + 1), 2); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE), 1);
        assertEq(ContinuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE - 1), 1); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp(1, (_EXP_SCALED_ONE / 2) + 1), 1); // Different than multiplyDown
        assertEq(ContinuousIndexingMath.multiplyUp(2, (_EXP_SCALED_ONE / 2)), 1);
        assertEq(ContinuousIndexingMath.multiplyUp(2, (_EXP_SCALED_ONE / 2) - 1), 1); // Different than multiplyDown
    }

    function test_exponent() external {
        assertEq(ContinuousIndexingMath.exponent(0), 1_000000000000); // actual 1

        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE / 10000), 1_000100005000); // actual 1.0001000050001667
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE / 1000), 1_001000500166); // actual 1.0010005001667084
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE / 100), 1_010050167084); // actual 1.010050167084168
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE / 10), 1_105170918075); // actual 1.1051709180756477
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE / 2), 1_648721270572); // actual 1.6487212707001282
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE), 2_718281718281); // actual 2.718281828459045
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE * 2), 7_388888888888); // actual 7.3890560989306495

        // Demonstrate maximum of ~200e12.
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE * 5), 128_619047619047);
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE * 6), 196_000000000000);
        assertEq(ContinuousIndexingMath.exponent(_EXP_SCALED_ONE * 7), 159_260869565217);

        // If `unchecked` is removed from `exponent`, it will not overflow (lot's of error nonetheless).
        assertEq(ContinuousIndexingMath.exponent(type(uint72).max), 1_000000008470);
    }

    function test_getContinuousIndex() external {
        assertEq(ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 0), 1_000000000000); // 1
        assertEq(ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 1 days), 1_002743482506); // 1.00274348
        assertEq(ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 10 days), 1_027776016255); // 1.02777602
        assertEq(ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 365 days), 2718281718281); // 2.71828183
    }

    function test_multiplyContinuousRates() external {
        uint256 oneHourRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 1 hours);
        uint256 twoHourRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 2 hours);
        uint256 fourHourRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 4 hours);
        uint256 sixteenHourRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 16 hours);
        uint256 oneDayRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 1 days);
        uint256 twoDayRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 2 days);

        uint256 oneInExp = uint256(_EXP_SCALED_ONE);

        assertEqPrecision((oneHourRate * oneHourRate) / oneInExp, twoHourRate, 1e1);

        assertEqPrecision(
            (oneHourRate * oneHourRate * oneHourRate * oneHourRate) / (oneInExp * oneInExp * oneInExp),
            fourHourRate,
            1e2
        );

        assertEqPrecision(
            (fourHourRate * fourHourRate * fourHourRate * fourHourRate) / (oneInExp * oneInExp * oneInExp),
            sixteenHourRate,
            1e1
        );

        assertEqPrecision((sixteenHourRate * fourHourRate * fourHourRate) / (oneInExp * oneInExp), oneDayRate, 1e1);

        assertEqPrecision(
            (sixteenHourRate * sixteenHourRate * sixteenHourRate) / (oneInExp * oneInExp),
            twoDayRate,
            1e1
        );

        assertEqPrecision((oneDayRate * oneDayRate) / oneInExp, twoDayRate, 1e1);
    }

    function test_multiplyThenDivide_100apy() external {
        uint112 amount = 1_000e6;
        uint128 sevenDayRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 7 days);
        uint128 thirtyDayRate = ContinuousIndexingMath.getContinuousIndex(_EXP_SCALED_ONE, 30 days);

        assertEq(
            ContinuousIndexingMath.divideDown(ContinuousIndexingMath.multiplyDown(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiplyDown(ContinuousIndexingMath.divideDown(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );

        assertEq(
            ContinuousIndexingMath.divideDown(
                ContinuousIndexingMath.multiplyDown(amount, thirtyDayRate),
                thirtyDayRate
            ),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiplyDown(
                ContinuousIndexingMath.divideDown(amount, thirtyDayRate),
                thirtyDayRate
            ),
            amount - 1
        );
    }

    function test_multiplyThenDivide_6apy() external {
        uint112 amount = 1_000e6;
        uint128 sevenDayRate = ContinuousIndexingMath.getContinuousIndex((_EXP_SCALED_ONE * 6) / 100, 7 days);
        uint128 thirtyDayRate = ContinuousIndexingMath.getContinuousIndex((_EXP_SCALED_ONE * 6) / 100, 30 days);

        assertEq(
            ContinuousIndexingMath.divideDown(ContinuousIndexingMath.multiplyDown(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiplyDown(ContinuousIndexingMath.divideDown(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );

        assertEq(
            ContinuousIndexingMath.divideDown(
                ContinuousIndexingMath.multiplyDown(amount, thirtyDayRate),
                thirtyDayRate
            ),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiplyDown(
                ContinuousIndexingMath.divideDown(amount, thirtyDayRate),
                thirtyDayRate
            ),
            amount - 1
        );
    }

    function test_convertToBasisPoints() external {
        assertEq(ContinuousIndexingMath.convertToBasisPoints(1_000000000000), 10_000);
        assertEq(ContinuousIndexingMath.convertToBasisPoints(type(uint64).max), 4078814_305);
    }

    function test_convertFromBasisPoints() external {
        assertEq(ContinuousIndexingMath.convertFromBasisPoints(10_000), 1_000000000000);
        assertEq(ContinuousIndexingMath.convertFromBasisPoints(type(uint32).max), 429496_729500000000);
    }

    function test_exponentLimits() external {
        uint72 x = 6_101171897009;
        uint48 maxExponent = 196_691035579299;

        assertEq(ContinuousIndexingMath.exponent(x), maxExponent); // Max of exponent.

        uint256 maxYearlyRateGivenHourlyUpdates = (x * 365 days) / 1 hours;
        uint256 maxYearlyRateGivenYearlyUpdates = (x * 365 days) / 365 days;

        assertEq(maxYearlyRateGivenHourlyUpdates, 53446_265817798840); // 5,344,626%
        assertEq(maxYearlyRateGivenYearlyUpdates, 6_101171897009); // 610%

        assertTrue(maxYearlyRateGivenHourlyUpdates < type(uint64).max);
        assertTrue(maxYearlyRateGivenYearlyUpdates < type(uint64).max);

        assertEq(ContinuousIndexingMath.convertToBasisPoints(uint64(maxYearlyRateGivenHourlyUpdates)), 534462_658); // 5,344,626.58%
        assertEq(ContinuousIndexingMath.convertToBasisPoints(uint64(maxYearlyRateGivenYearlyUpdates)), 61_011); // 610.11%

        assertEq(
            ContinuousIndexingMath.getContinuousIndex(uint64(maxYearlyRateGivenHourlyUpdates), 1 hours),
            196_691035579299
        );
        assertEq(
            ContinuousIndexingMath.getContinuousIndex(uint64(maxYearlyRateGivenYearlyUpdates), 365 days),
            196_691035579299
        );
    }

    function test_indexLimits_hourlyAt1000APY() external {
        // 6 years of hourly updates at 1000% APY.
        uint128 index = _EXP_SCALED_ONE;

        for (uint256 i; i < 52_560; ++i) {
            index = safe128(
                ContinuousIndexingMath.multiplyIndices(
                    index,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(100_000), // 1000%
                        1 hours
                    )
                )
            );
        }

        assertEq(index, 114200736000519624644263162621717068785);
    }

    function test_indexLimits_dailyAt100APY() external {
        // 60 years of daily updates at 100% APY.
        uint128 index = _EXP_SCALED_ONE;

        for (uint256 i; i < 21_900; ++i) {
            index = safe128(
                ContinuousIndexingMath.multiplyIndices(
                    index,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(10_000), // 100%
                        1 days
                    )
                )
            );
        }

        assertEq(index, 114200737611197117821646215174647287334);
    }

    function test_indexLimits_dailyAt10APY() external {
        // 600 years of daily updates at 10% APY.
        uint128 index = _EXP_SCALED_ONE;

        for (uint256 i; i < 219_000; ++i) {
            index = safe128(
                ContinuousIndexingMath.multiplyIndices(
                    index,
                    ContinuousIndexingMath.getContinuousIndex(
                        ContinuousIndexingMath.convertFromBasisPoints(1_000), // 10%
                        1 days
                    )
                )
            );
        }

        assertEq(index, 114200697247308241422562109115999467493);
    }

    function safe128(uint256 n) internal pure returns (uint128) {
        if (n > type(uint128).max) revert();
        return uint128(n);
    }

    function assertEqPrecision(uint256 a_, uint256 b_, uint256 precision_) internal {
        if (a_ / precision_ != b_ / precision_) {
            emit log("Error: a == b not satisfied [uint]");
            emit log_named_uint("      Left", a_);
            emit log_named_uint("     Right", b_);
            fail();
        }
    }
}
