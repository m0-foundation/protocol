// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../../lib/forge-std/src/Test.sol";
import { ContinuousIndexingMath } from "../../../src/libs/ContinuousIndexingMath.sol";

contract ContinuousIndexingMathTest is Test {

    function test_divide() public {
        // result is converted to 1 = 1*10^18 --> result * 1*10^18
        assertEq(100_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                         1));
        assertEq( 50_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                         2));
        assertEq(  1_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                       100));
        assertEq(    100_000_000_000_000_000, ContinuousIndexingMath.divide(100,                     1_000));
        assertEq(                          1, ContinuousIndexingMath.divide(  1, 1_000_000_000_000_000_000));
        // losing the precision from here
        assertEq(                          0, ContinuousIndexingMath.divide(  1, 2_000_000_000_000_000_000));
    }

    function test_multiply() public {
        // result is converted to 1 = 1 --> result / 1*10^18
        assertEq(100, ContinuousIndexingMath.multiply(100_000_000_000_000_000_000,                           1));
        assertEq(100, ContinuousIndexingMath.multiply( 50_000_000_000_000_000_000,                           2));
        assertEq(100, ContinuousIndexingMath.multiply(  1_000_000_000_000_000_000,                         100));
        assertEq(100, ContinuousIndexingMath.multiply(    100_000_000_000_000_000,                       1_000));
        assertEq(  1, ContinuousIndexingMath.multiply(                         1 ,   1_000_000_000_000_000_000));
    }

    function test_getContinuousIndex() public {
        // this is used to calculate a factor for compounding interest
        assertEq(1_105_170_833_333_333_332, ContinuousIndexingMath.getContinuousIndex(100_000_000_000_000_000, 365 days * 1));  // factor for 10% after one year 
        assertEq(1_221_399_999_999_999_999, ContinuousIndexingMath.getContinuousIndex(100_000_000_000_000_000, 365 days * 2));  // factor for 10% after two years 
        assertEq(2_708_333_333_333_333_332, ContinuousIndexingMath.getContinuousIndex(100_000_000_000_000_000, 365 days * 10)); // factor for 10% after ten years 

        assertEq(1_005_012_520_859_374_999, ContinuousIndexingMath.getContinuousIndex(  5_000_000_000_000_000, 365 days * 1));  // factor for 0.5% after one year 
        assertEq(1_010_050_167_083_333_332, ContinuousIndexingMath.getContinuousIndex(  5_000_000_000_000_000, 365 days * 2));  // factor for 0.5% after two years 
        assertEq(1_051_271_093_749_999_999, ContinuousIndexingMath.getContinuousIndex(  5_000_000_000_000_000, 365 days * 10)); // factor for 0.5% after ten years

        assertEq(1_000_054_796_021_795_105, ContinuousIndexingMath.getContinuousIndex( 20_000_000_000_000_000,   1 days));      // factor for 2% after 1 day
        assertEq(1_000_383_635_213_008_728, ContinuousIndexingMath.getContinuousIndex( 20_000_000_000_000_000,   7 days));      // factor for 2% after 7 days
        assertEq(1_001_645_187_454_837_078, ContinuousIndexingMath.getContinuousIndex( 20_000_000_000_000_000,  30 days));      // factor for 2% after 30 days
    }

    function test_exponent() public {
        // tailor function is used to approximate euler 
        assertEq(644333333333333333332, ContinuousIndexingMath.exponent(10_000_000_000_000_000_000)); // e^10
        assertEq( 65374999999999999999, ContinuousIndexingMath.exponent( 5_000_000_000_000_000_000)); // e^5 
        assertEq(  2708333333333333332, ContinuousIndexingMath.exponent( 1_000_000_000_000_000_000)); // e^1 
        assertEq(  1105170833333333332, ContinuousIndexingMath.exponent(   100_000_000_000_000_000)); // e^0.1 
        assertEq(  1010050167083333332, ContinuousIndexingMath.exponent(    10_000_000_000_000_000)); // e^0.01 
        assertEq(  1001000500166708332, ContinuousIndexingMath.exponent(     1_000_000_000_000_000)); // e^0.01 
    }

    function test_convertToBasisPoints() public {
        assertEq(10_000, ContinuousIndexingMath.convertToBasisPoints(1_000_000_000_000_000_000)); // 100.00 %
        assertEq( 1_000, ContinuousIndexingMath.convertToBasisPoints(  100_000_000_000_000_000)); //  10.00 % 
        assertEq(   100, ContinuousIndexingMath.convertToBasisPoints(   10_000_000_000_000_000)); //   1.00 %
        assertEq(    10, ContinuousIndexingMath.convertToBasisPoints(    1_000_000_000_000_000)); //   0.10 %
        assertEq(     1, ContinuousIndexingMath.convertToBasisPoints(      100_000_000_000_000)); //   0.01 %
        assertEq(     0, ContinuousIndexingMath.convertToBasisPoints(        1_000_000_000_000)); // < 0.01 %
    }
                                                                     
    function test_convertFromBasisPoints() public {
        assertEq(1_000_000_000_000_000_000, ContinuousIndexingMath.convertFromBasisPoints(10_000)); // 100.00 %
        assertEq(  100_000_000_000_000_000, ContinuousIndexingMath.convertFromBasisPoints( 1_000)); //  10.00 % 
        assertEq(   10_000_000_000_000_000, ContinuousIndexingMath.convertFromBasisPoints(   100)); //   1.00 %
        assertEq(    1_000_000_000_000_000, ContinuousIndexingMath.convertFromBasisPoints(    10)); //   0.10 %
        assertEq(      100_000_000_000_000, ContinuousIndexingMath.convertFromBasisPoints(     1)); //   0.01 %
    }
 

}
