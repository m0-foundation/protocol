// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";

contract MTokenTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");

    address internal _protocol = makeAddr("protocol");

    MToken internal _mToken;

    function setUp() external {
        _mToken = new MToken(_protocol);
    }

    function test_mint() external {
        assertEq(_mToken.balanceOf(_alice), 0);

        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);
    }

    function test_mint_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.mint(_alice, 1_000);
    }

    function test_burn() external {
        assertEq(_mToken.balanceOf(_alice), 0);

        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
    }

    function test_burn_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.burn(_alice, 1_000);
    }
}
