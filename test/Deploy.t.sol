// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

import { IMinterGateway } from "../src/interfaces/IMinterGateway.sol";
import { IMToken } from "../src/interfaces/IMToken.sol";
import { IEarnerRateModel } from "../src/rateModels/interfaces/IEarnerRateModel.sol";
import { IMinterRateModel } from "../src/rateModels/interfaces/IMinterRateModel.sol";

import { DeployBase } from "../script/DeployBase.sol";

import { MockTTGRegistrar } from "./utils/Mocks.sol";

contract Deploy is Test, DeployBase {
    address internal constant _TTG_VAULT = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

    MockTTGRegistrar internal _ttgRegistrar;

    function setUp() external {
        _ttgRegistrar = new MockTTGRegistrar();
        _ttgRegistrar.setVault(_TTG_VAULT);
    }

    function test_deploy() external {
        (address minterGateway_, address minterRateModel_, address earnerRateModel_) = deploy(
            address(this),
            2,
            address(_ttgRegistrar)
        );

        address mToken_ = getExpectedMToken(address(this), 2);

        // Minter Gateway assertions
        assertEq(minterGateway_, getExpectedMinterGateway(address(this), 2));
        assertEq(IMinterGateway(minterGateway_).ttgRegistrar(), address(_ttgRegistrar));
        assertEq(IMinterGateway(minterGateway_).ttgVault(), _TTG_VAULT);
        assertEq(IMinterGateway(minterGateway_).mToken(), mToken_);

        // MToken assertions
        assertEq(IMToken(mToken_).minterGateway(), minterGateway_);
        assertEq(IMToken(mToken_).ttgRegistrar(), address(_ttgRegistrar));

        // Minter Rate Model assertions
        assertEq(minterRateModel_, getExpectedMinterRateModel(address(this), 2));
        assertEq(IMinterRateModel(minterRateModel_).ttgRegistrar(), address(_ttgRegistrar));

        // Earner Rate Model assertions
        assertEq(earnerRateModel_, getExpectedEarnerRateModel(address(this), 2));
        assertEq(IEarnerRateModel(earnerRateModel_).mToken(), mToken_);
        assertEq(IEarnerRateModel(earnerRateModel_).minterGateway(), minterGateway_);
        assertEq(IEarnerRateModel(earnerRateModel_).ttgRegistrar(), address(_ttgRegistrar));
    }
}
