// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { stdError, Test } from "../lib/forge-std/src/Test.sol";

import { UIntMath } from "../src/libs/UIntMath.sol";

contract UIntMathTests is Test {
    function test_safe40() external {
        assertEq(UIntMath.safe40(2 ** 40 - 1), 2 ** 40 - 1);

        vm.expectRevert(UIntMath.InvalidUInt40.selector);
        UIntMath.safe40(2 ** 40);
    }

    function test_safe48() external {
        assertEq(UIntMath.safe48(2 ** 48 - 1), 2 ** 48 - 1);

        vm.expectRevert(UIntMath.InvalidUInt48.selector);
        UIntMath.safe48(2 ** 48);
    }

    function test_safe128() external {
        assertEq(UIntMath.safe128(2 ** 128 - 1), 2 ** 128 - 1);

        vm.expectRevert(UIntMath.InvalidUInt128.selector);
        UIntMath.safe128(2 ** 128);
    }

    function test_bound32() external {
        assertEq(UIntMath.bound32(2 ** 32), 2 ** 32 - 1);
    }

    function test_max40() external {
        assertEq(UIntMath.max40(1, 2), 2);
        assertEq(UIntMath.max40(2, 1), 2);
    }

    function test_min32() external {
        assertEq(UIntMath.min32(1, 2), 1);
        assertEq(UIntMath.min32(2, 1), 1);
    }

    function test_min40() external {
        assertEq(UIntMath.min40(1, 2), 1);
        assertEq(UIntMath.min40(2, 1), 1);
    }

    function test_min128() external {
        assertEq(UIntMath.min128(1, 2), 1);
        assertEq(UIntMath.min128(2, 1), 1);
    }

    function test_min256() external {
        assertEq(UIntMath.min256(1, 2), 1);
        assertEq(UIntMath.min256(2, 1), 1);
    }

    function test_min40IgnoreZero() external {
        assertEq(UIntMath.min40IgnoreZero(0, 0), 0);
        assertEq(UIntMath.min40IgnoreZero(0, 1), 1);
        assertEq(UIntMath.min40IgnoreZero(1, 0), 1);
        assertEq(UIntMath.min40IgnoreZero(1, 2), 1);
        assertEq(UIntMath.min40IgnoreZero(2, 1), 1);
    }
}
