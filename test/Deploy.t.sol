// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { DeployBase } from "../script/DeployBase.sol";

import { MockRegistrar } from "./utils/Mocks.sol";

contract Deploy is Test, DeployBase {
    MockRegistrar internal _registrar;

    address internal _portal = makeAddr("portal");

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setPortal(_portal);
    }

    function test_deploy() external {
        address mToken_ = deploy(address(_registrar));

        assertEq(mToken_, getExpectedMToken(address(this), 2));

        // MToken assertions
        assertEq(IMToken(mToken_).portal(), _portal);
        assertEq(IMToken(mToken_).registrar(), address(_registrar));
    }
}
