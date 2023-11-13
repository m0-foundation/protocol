// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { InterestMath } from "../src/libs/InterestMath.sol";

contract InterestMathTests is Test {
    uint256 constant ONE_IN_EXP = InterestMath.EXP_BASE_SCALE;

    function test_exponent() external {
        assertEq(InterestMath.exponent(0), 1000000000000000000); // 1

        assertEq(InterestMath.exponent(ONE_IN_EXP / 10000), 1000100005000166670); // 1.0001000050001667
        assertEq(InterestMath.exponent(ONE_IN_EXP / 1000), 1001000500166708332); // 1.0010005001667084
        assertEq(InterestMath.exponent(ONE_IN_EXP / 100), 1010050167083333332); // 1.010050167084168
        assertEq(InterestMath.exponent(ONE_IN_EXP / 10), 1105170833333333332); // 1.1051709180756477
        assertEq(InterestMath.exponent(ONE_IN_EXP / 2), 1648437499999999999); // 1.6487212707001282
        assertEq(InterestMath.exponent(ONE_IN_EXP), 2708333333333333332); // 2.718281828459045
        assertEq(InterestMath.exponent(ONE_IN_EXP * 2), 6999999999999999999); // 7.3890560989306495
    }

    function test_getContinuousRate() external {
        assertEq(InterestMath.getContinuousRate(ONE_IN_EXP, 0),  1000000000000000000); // 1
        assertEq(InterestMath.getContinuousRate(ONE_IN_EXP, 1 days),  1002743482506539752); // 1.00274348
        assertEq(InterestMath.getContinuousRate(ONE_IN_EXP, 10 days), 1027776016127196045); // 1.02777602
        assertEq(InterestMath.getContinuousRate(ONE_IN_EXP, 365 days), 2708333333333333332); // 2.71828183
    }

    function test_multiplyContinuousRates() external {
        uint256 oneHourRate = InterestMath.getContinuousRate(ONE_IN_EXP, 1 hours);
        uint256 twoHourRate = InterestMath.getContinuousRate(ONE_IN_EXP, 2 hours);
        uint256 fourHourRate = InterestMath.getContinuousRate(ONE_IN_EXP, 4 hours);
        uint256 sixteenHourRate = InterestMath.getContinuousRate(ONE_IN_EXP, 16 hours);
        uint256 oneDayRate = InterestMath.getContinuousRate(ONE_IN_EXP, 1 days);
        uint256 twoDayRate = InterestMath.getContinuousRate(ONE_IN_EXP, 2 days);

        assertEq(oneHourRate * oneHourRate / (ONE_IN_EXP * 10), twoHourRate / 10); // within 1 decimal precision
        assertEq(
            oneHourRate * oneHourRate * oneHourRate * oneHourRate / (ONE_IN_EXP * ONE_IN_EXP * ONE_IN_EXP * 10),
            fourHourRate / 10
        ); // within 1 decimal precision
        assertEq(
            fourHourRate * fourHourRate * fourHourRate * fourHourRate / (ONE_IN_EXP * ONE_IN_EXP * ONE_IN_EXP * 1_000),
            sixteenHourRate / 1_000
        ); // within 3 decimal precision
        assertEq(
            sixteenHourRate * fourHourRate * fourHourRate / (ONE_IN_EXP * ONE_IN_EXP * 100_000),
            oneDayRate / 100_000
        ); // within 5 decimal precision
        assertEq(
            sixteenHourRate * sixteenHourRate * sixteenHourRate / (ONE_IN_EXP * ONE_IN_EXP * 100_000),
            twoDayRate / 100_000
        ); // within 5 decimal precision
        assertEq(oneDayRate * oneDayRate / (ONE_IN_EXP * 100_000), twoDayRate / 100_000); // within 5 decimal precision
    }

    function test_multiplyThenDivide_100apy() external {
        uint256 amount = 1_000e6;
        uint256 sevenDayRate = InterestMath.getContinuousRate(ONE_IN_EXP, 7 days);
        uint256 thirtyDayRate = InterestMath.getContinuousRate(ONE_IN_EXP, 30 days);

        assertEq(InterestMath.divide(InterestMath.multiply(amount, sevenDayRate), sevenDayRate), amount - 1);
        assertEq(InterestMath.multiply(InterestMath.divide(amount, sevenDayRate), sevenDayRate), amount - 1);

        assertEq(InterestMath.divide(InterestMath.multiply(amount, thirtyDayRate), thirtyDayRate), amount - 1);
        assertEq(InterestMath.multiply(InterestMath.divide(amount, thirtyDayRate), thirtyDayRate), amount - 1);
    }

    function test_multiplyThenDivide_6apy() external {
        uint256 amount = 1_000e6;
        uint256 sevenDayRate = InterestMath.getContinuousRate((ONE_IN_EXP * 6) / 100, 7 days);
        uint256 thirtyDayRate = InterestMath.getContinuousRate((ONE_IN_EXP * 6) / 100, 30 days);

        assertEq(InterestMath.divide(InterestMath.multiply(amount, sevenDayRate), sevenDayRate), amount - 1);
        assertEq(InterestMath.multiply(InterestMath.divide(amount, sevenDayRate), sevenDayRate), amount - 1);

        assertEq(InterestMath.divide(InterestMath.multiply(amount, thirtyDayRate), thirtyDayRate), amount - 1);
        assertEq(InterestMath.multiply(InterestMath.divide(amount, thirtyDayRate), thirtyDayRate), amount - 1);
    }
}
