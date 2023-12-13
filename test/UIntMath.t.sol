// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { stdError, Test } from "../lib/forge-std/src/Test.sol";

import { UIntMath } from "../src/libs/UIntMath.sol";

contract UIntMathTests is Test {
    function test_safe24() external {
        assertEq(UIntMath.safe24(2 ** 24 - 1), 2 ** 24 - 1);

        vm.expectRevert(UIntMath.InvalidUInt24.selector);
        UIntMath.safe24(2 ** 24);
    }

    function test_safe40() external {
        assertEq(UIntMath.safe40(2 ** 40 - 1), 2 ** 40 - 1);

        vm.expectRevert(UIntMath.InvalidUInt40.selector);
        UIntMath.safe40(2 ** 40);
    }

    function test_safe128() external {
        assertEq(UIntMath.safe128(2 ** 128 - 1), 2 ** 128 - 1);

        vm.expectRevert(UIntMath.InvalidUInt128.selector);
        UIntMath.safe128(2 ** 128);
    }

    function test_safe192() external {
        assertEq(UIntMath.safe192(2 ** 192 - 1), 2 ** 192 - 1);

        vm.expectRevert(UIntMath.InvalidUInt192.selector);
        UIntMath.safe192(2 ** 192);
    }
}
