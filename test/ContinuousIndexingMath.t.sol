// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

import { ContinuousIndexingMathHarness } from "./utils/ContinuousIndexingMathHarness.sol";

contract ContinuousIndexingMathTests is Test {
    uint56 internal constant _EXP_SCALED_ONE = ContinuousIndexingMath.EXP_SCALED_ONE;

    ContinuousIndexingMathHarness public continuousIndexingMath;

    function setUp() external {
        continuousIndexingMath = new ContinuousIndexingMathHarness();
    }

    function test_divideDown() external {
        // Set 1a
        assertEq(continuousIndexingMath.divideDown(0, 1), 0);
        assertEq(continuousIndexingMath.divideDown(1, 1), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(2, 1), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(3, 1), 3 * _EXP_SCALED_ONE);

        // Set 1b
        assertEq(continuousIndexingMath.divideDown(1, 1), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(1, 2), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideDown(1, 3), _EXP_SCALED_ONE / 3); // Different than divideUp

        // Set 2a
        assertEq(continuousIndexingMath.divideDown(0, 10), 0);
        assertEq(continuousIndexingMath.divideDown(5, 10), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideDown(10, 10), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(15, 10), _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideDown(20, 10), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(25, 10), 2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);

        // Set 2b
        assertEq(continuousIndexingMath.divideDown(10, 5), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(10, 10), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideDown(10, 15), (2 * _EXP_SCALED_ONE) / 3); // Different than divideUp
        assertEq(continuousIndexingMath.divideDown(10, 20), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideDown(10, 25), (2 * _EXP_SCALED_ONE) / 5);

        // Set 3
        assertEq(continuousIndexingMath.divideDown(1, _EXP_SCALED_ONE + 1), 0); // Different than divideUp
        assertEq(continuousIndexingMath.divideDown(1, _EXP_SCALED_ONE), 1);
        assertEq(continuousIndexingMath.divideDown(1, _EXP_SCALED_ONE - 1), 1); // Different than divideUp
        assertEq(continuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2) + 1), 1); // Different than divideUp
        assertEq(continuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2)), 2);
        assertEq(continuousIndexingMath.divideDown(1, (_EXP_SCALED_ONE / 2) - 1), 2); // Different than divideUp
    }

    function test_divideUp() external {
        // Set 1a
        assertEq(continuousIndexingMath.divideUp(0, 1), 0);
        assertEq(continuousIndexingMath.divideUp(1, 1), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(2, 1), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(3, 1), 3 * _EXP_SCALED_ONE);

        // Set 1b
        assertEq(continuousIndexingMath.divideUp(1, 1), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(1, 2), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideUp(1, 3), _EXP_SCALED_ONE / 3 + 1); // Different than divideDown

        // Set 2a
        assertEq(continuousIndexingMath.divideUp(0, 10), 0);
        assertEq(continuousIndexingMath.divideUp(5, 10), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideUp(10, 10), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(15, 10), _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideUp(20, 10), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(25, 10), 2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2);

        // Set 2b
        assertEq(continuousIndexingMath.divideUp(10, 5), 2 * _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(10, 10), _EXP_SCALED_ONE);
        assertEq(continuousIndexingMath.divideUp(10, 15), (2 * _EXP_SCALED_ONE) / 3 + 1); // Different than divideDown
        assertEq(continuousIndexingMath.divideUp(10, 20), _EXP_SCALED_ONE / 2);
        assertEq(continuousIndexingMath.divideUp(10, 25), (2 * _EXP_SCALED_ONE) / 5);

        // Set 3
        assertEq(continuousIndexingMath.divideUp(1, _EXP_SCALED_ONE + 1), 1); // Different than divideDown
        assertEq(continuousIndexingMath.divideUp(1, _EXP_SCALED_ONE), 1);
        assertEq(continuousIndexingMath.divideUp(1, _EXP_SCALED_ONE - 1), 2); // Different than divideDown
        assertEq(continuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2) + 1), 2); // Different than divideDown
        assertEq(continuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2)), 2);
        assertEq(continuousIndexingMath.divideUp(1, (_EXP_SCALED_ONE / 2) - 1), 3); // Different than divideDown
    }

    function test_multiplyDown() external {
        // Set 1a
        assertEq(continuousIndexingMath.multiplyDown(0, 1), 0);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 1), 1);
        assertEq(continuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 1), 2);
        assertEq(continuousIndexingMath.multiplyDown(3 * _EXP_SCALED_ONE, 1), 3);

        // Set 1b
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 1), 1);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 2), 1);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 3, 3), 0);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 3 + 1, 3), 1);

        // Set 2a
        assertEq(continuousIndexingMath.multiplyDown(0, 10), 0);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 10), 5);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 10), 10);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 15);
        assertEq(continuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 10), 20);
        assertEq(continuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 25);

        // Set 2b
        assertEq(continuousIndexingMath.multiplyDown(2 * _EXP_SCALED_ONE, 5), 10);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE, 10), 10);
        assertEq(continuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 3, 15), 9);
        assertEq(continuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 3 + 1, 15), 10);
        assertEq(continuousIndexingMath.multiplyDown(_EXP_SCALED_ONE / 2, 20), 10);
        assertEq(continuousIndexingMath.multiplyDown((2 * _EXP_SCALED_ONE) / 5, 25), 10);

        // Set 3
        assertEq(continuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE + 1), 1);
        assertEq(continuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE), 1);
        assertEq(continuousIndexingMath.multiplyDown(1, _EXP_SCALED_ONE - 1), 0);
        assertEq(continuousIndexingMath.multiplyDown(1, (_EXP_SCALED_ONE / 2) + 1), 0);
        assertEq(continuousIndexingMath.multiplyDown(2, (_EXP_SCALED_ONE / 2)), 1);
        assertEq(continuousIndexingMath.multiplyDown(2, (_EXP_SCALED_ONE / 2) - 1), 0);
    }

    function test_multiplyUp() external {
        // Set 1a
        assertEq(continuousIndexingMath.multiplyUp(0, 1), 0);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 1), 1);
        assertEq(continuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 1), 2);
        assertEq(continuousIndexingMath.multiplyUp(3 * _EXP_SCALED_ONE, 1), 3);

        // Set 1b
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 1), 1);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 2), 1);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 3, 3), 1); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 3 + 1, 3), 2); // Different than multiplyDown

        // Set 2a
        assertEq(continuousIndexingMath.multiplyUp(0, 10), 0);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 10), 5);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 10), 10);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 15);
        assertEq(continuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 10), 20);
        assertEq(continuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE + _EXP_SCALED_ONE / 2, 10), 25);

        // Set 2b
        assertEq(continuousIndexingMath.multiplyUp(2 * _EXP_SCALED_ONE, 5), 10);
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE, 10), 10);
        assertEq(continuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 3, 15), 10); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 3 + 1, 15), 11); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp(_EXP_SCALED_ONE / 2, 20), 10);
        assertEq(continuousIndexingMath.multiplyUp((2 * _EXP_SCALED_ONE) / 5, 25), 10);

        // Set 3
        assertEq(continuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE + 1), 2); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE), 1);
        assertEq(continuousIndexingMath.multiplyUp(1, _EXP_SCALED_ONE - 1), 1); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp(1, (_EXP_SCALED_ONE / 2) + 1), 1); // Different than multiplyDown
        assertEq(continuousIndexingMath.multiplyUp(2, (_EXP_SCALED_ONE / 2)), 1);
        assertEq(continuousIndexingMath.multiplyUp(2, (_EXP_SCALED_ONE / 2) - 1), 1); // Different than multiplyDown
    }
}
