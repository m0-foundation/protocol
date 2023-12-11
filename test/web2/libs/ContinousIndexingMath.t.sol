// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../../lib/forge-std/src/Test.sol";
import { ContinuousIndexingMath } from "../../../src/libs/ContinuousIndexingMath.sol";



contract ContinuousIndexingMathTest is Test {


    function test_divide() public {
        assertEq(100_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                         1));
        assertEq( 50_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                         2));
        assertEq(  1_000_000_000_000_000_000, ContinuousIndexingMath.divide(100,                       100));
        assertEq(    100_000_000_000_000_000, ContinuousIndexingMath.divide(100,                     1_000));
        assertEq(                          1, ContinuousIndexingMath.divide(  1, 1_000_000_000_000_000_000));
        assertEq(                          0, ContinuousIndexingMath.divide(  1, 2_000_000_000_000_000_000));
    }

    function test_multiply() public {
    }

    function test_getContinuousIndex() public {
    }

    function test_exponent() public {
        console2.logUint(ContinuousIndexingMath.exponent(1));
        console2.logUint(ContinuousIndexingMath.exponent(1));
        console2.logUint(ContinuousIndexingMath.exponent(1));
        console2.logUint(ContinuousIndexingMath.exponent(1));
        console2.logUint(ContinuousIndexingMath.exponent(1));
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
