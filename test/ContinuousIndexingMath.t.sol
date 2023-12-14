// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

contract ContinuousIndexingMathTests is Test {
    uint56 constant EXP_ONE = ContinuousIndexingMath.EXP_ONE;

    function test_exponent() external {
        assertEq(ContinuousIndexingMath.exponent(0), 1_000000000000); // actual 1

        assertEq(ContinuousIndexingMath.exponent(EXP_ONE / 10000), 1_000100005000); // actual 1.0001000050001667
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE / 1000), 1_001000500166); // actual 1.0010005001667084
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE / 100), 1_010050167084); // actual 1.010050167084168
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE / 10), 1_105170918075); // actual 1.1051709180756477
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE / 2), 1_648721270572); // actual 1.6487212707001282
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE), 2_718281718281); // actual 2.718281828459045
        assertEq(ContinuousIndexingMath.exponent(EXP_ONE * 2), 7_388888888888); // actual 7.3890560989306495
    }

    function test_getContinuousIndex() external {
        assertEq(ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 0), 1_000000000000); // 1
        assertEq(ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 1 days), 1_002743482506); // 1.00274348
        assertEq(ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 10 days), 1_027776016255); // 1.02777602
        assertEq(ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 365 days), 2718281718281); // 2.71828183
    }

    function test_multiplyContinuousRates() external {
        uint256 oneHourRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 1 hours);
        uint256 twoHourRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 2 hours);
        uint256 fourHourRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 4 hours);
        uint256 sixteenHourRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 16 hours);
        uint256 oneDayRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 1 days);
        uint256 twoDayRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 2 days);

        uint256 oneInExp = uint256(EXP_ONE);

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
        uint128 amount = 1_000e6;
        uint128 sevenDayRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 7 days);
        uint128 thirtyDayRate = ContinuousIndexingMath.getContinuousIndex(EXP_ONE, 30 days);

        assertEq(
            ContinuousIndexingMath.divide(ContinuousIndexingMath.multiply(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiply(ContinuousIndexingMath.divide(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );

        assertEq(
            ContinuousIndexingMath.divide(ContinuousIndexingMath.multiply(amount, thirtyDayRate), thirtyDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiply(ContinuousIndexingMath.divide(amount, thirtyDayRate), thirtyDayRate),
            amount - 1
        );
    }

    function test_multiplyThenDivide_6apy() external {
        uint128 amount = 1_000e6;
        uint128 sevenDayRate = ContinuousIndexingMath.getContinuousIndex((EXP_ONE * 6) / 100, 7 days);
        uint128 thirtyDayRate = ContinuousIndexingMath.getContinuousIndex((EXP_ONE * 6) / 100, 30 days);

        assertEq(
            ContinuousIndexingMath.divide(ContinuousIndexingMath.multiply(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiply(ContinuousIndexingMath.divide(amount, sevenDayRate), sevenDayRate),
            amount - 1
        );

        assertEq(
            ContinuousIndexingMath.divide(ContinuousIndexingMath.multiply(amount, thirtyDayRate), thirtyDayRate),
            amount - 1
        );
        assertEq(
            ContinuousIndexingMath.multiply(ContinuousIndexingMath.divide(amount, thirtyDayRate), thirtyDayRate),
            amount - 1
        );
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
