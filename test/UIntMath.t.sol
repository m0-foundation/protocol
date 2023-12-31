// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { UIntMath } from "../src/libs/UIntMath.sol";

contract UIntMathTests is Test {
    function test_safe40() external {
        assertEq(UIntMath.safe40(uint256(type(uint40).max)), type(uint40).max);

        vm.expectRevert(UIntMath.InvalidUInt40.selector);
        UIntMath.safe40(uint256(type(uint40).max) + 1);
    }

    function test_safe48() external {
        assertEq(UIntMath.safe48(uint256(type(uint48).max)), type(uint48).max);

        vm.expectRevert(UIntMath.InvalidUInt48.selector);
        UIntMath.safe48(uint256(type(uint48).max) + 1);
    }

    function test_safe112() external {
        assertEq(UIntMath.safe112(uint256(type(uint112).max)), type(uint112).max);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        UIntMath.safe112(uint256(type(uint112).max) + 1);
    }

    function test_safe128() external {
        assertEq(UIntMath.safe128(uint256(type(uint128).max)), type(uint128).max);

        vm.expectRevert(UIntMath.InvalidUInt128.selector);
        UIntMath.safe128(uint256(type(uint128).max) + 1);
    }

    function test_safe240() external {
        assertEq(UIntMath.safe240(uint256(type(uint240).max)), type(uint240).max);

        vm.expectRevert(UIntMath.InvalidUInt240.selector);
        UIntMath.safe240(uint256(type(uint240).max) + 1);
    }

    function test_bound32() external {
        assertEq(UIntMath.bound32(uint256(type(uint32).max) + 1), type(uint32).max);
    }

    function test_bound112() external {
        assertEq(UIntMath.bound112(uint256(type(uint112).max) + 1), type(uint112).max);
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

    function test_min240() external {
        assertEq(UIntMath.min240(1, 2), 1);
        assertEq(UIntMath.min240(2, 1), 1);
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
