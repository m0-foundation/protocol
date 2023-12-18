// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { MToken } from "../../src/MToken.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IRateModel } from "../../src/interfaces/IRateModel.sol";
import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";
import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";
//import { IEarnerRateModel } from "../../src/interfaces/IEarnerRateModel.sol";
//import { IMinterRateModel } from "../../src/interfaces/IMinterRateModel.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import {MTokenHarness} from "./util/MTokenHarness.sol";

contract MTokenTest is Test {
    address internal _protocolAddress = makeAddr("protocol");
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _earnerRateModelAddress = makeAddr("earnerRateModel");
    address internal _aliceAddress = makeAddr("alice");
    address internal _bobAddress = makeAddr("bob");
    uint256 internal _start = block.timestamp;

    MTokenHarness internal _mToken;
    uint256 internal _earnerRate = 100; // 10% (1000 = 100%)


    function setUp() public
    {
        _mToken = new MTokenHarness(_spogRegistrarAddress, _protocolAddress);

        // set address of earner model
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.EARNER_RATE_MODEL),
            abi.encode(_earnerRateModelAddress)
        ); 

        // set earning rate of earner model 
        vm.mockCall(
            _earnerRateModelAddress,
            abi.encodeWithSelector(IRateModel.rate.selector),
            abi.encode(_earnerRate)
        );
    }

    function test_setUp() public {
        assertEq(_protocolAddress, _mToken.protocol(), "Setup protocol address failed");
        assertEq(_spogRegistrarAddress, _mToken.spogRegistrar(), "Setup spogRegistrar address failed");
        assertEq(_earnerRateModelAddress, _mToken.rateModel(), "Setup earner rate address failed");
        assertEq(_earnerRate, IRateModel(_earnerRateModelAddress).rate(), "Setup earner rate failed");
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    function test_mint_NotProtocol() public {
        vm.expectRevert(IMToken.NotProtocol.selector);
        vm.prank(_aliceAddress);
        _mToken.mint(_aliceAddress, 1000);
    }


    function test_mint_aliceNotEarning() public {
        // Look for events
        vm.expectEmit(true, true, false, true, address(_mToken));
        emit IERC20.Transfer(address(0), _aliceAddress, 1337);

        // Execute method
        vm.prank(_protocolAddress);
        _mToken.mint(_aliceAddress, 1337);

        // balance for alice increased
        assertEq(_mToken.balanceOf(_aliceAddress), 1337);
        // totalNonEarningSupply increased
        assertEq(_mToken.totalNonEarningSupply(), 1337);

        assertEq(_mToken.totalSupply(), 1337);
        assertEq(_mToken.totalEarningSupply(), 0);
        assertFalse(_mToken.isEarning(_aliceAddress));
        assertFalse(_mToken.hasOptedOutOfEarning(_aliceAddress));
    }

    function test_mint_aliceEarning() public 
    {
        _mToken.setter_latestRate(_earnerRate);
        _mToken.setter_isEarning(_aliceAddress, true);

        // time to reach index ±1.01
        // but why?? it's only 363.187 days
        vm.warp(_start + 31_379_364);

        vm.expectEmit(true, true, false, false);
        emit IContinuousIndexing.IndexUpdated(1_010_000_000_198_216_635, 100);
        _mToken.updateIndex();

        vm.expectEmit(true, true, false, true, address(_mToken));
        emit IERC20.Transfer(address(0), _aliceAddress, 1_338_000);
        vm.prank(_protocolAddress);
        _mToken.mint(_aliceAddress, 1_338_000);

        // balance for alice increased
        assertEq(_mToken.getter_balance(_aliceAddress), 1_324_752);
        // totalNonEarningSupply increased
        assertEq(_mToken.getter_totalPrincipalOfEarningSupply(), 1_324_752);

        // rounding problem here
        assertApproxEqAbs(_mToken.balanceOf(_aliceAddress), 1_338_000, 1);
        // totalNonEarningSupply didn't change
        assertEq(_mToken.totalNonEarningSupply(), 0);

        assertApproxEqAbs(_mToken.totalSupply(),  1_338_000, 1);
        assertApproxEqAbs(_mToken.totalEarningSupply(), 1_338_000, 1);
        assertTrue(_mToken.isEarning(_aliceAddress));
        assertFalse(_mToken.hasOptedOutOfEarning(_aliceAddress));
    }

    function test_burn() public {

    }

    function test_optOutOfEarning() public {

    }

    function test_startEarning() public {

    }

    function test_startEarningForAddress() public {

    }

    function test_stopEarning() public {

    }

    function test_stopEarningForAddress() public 
    {

    }


    /******************************************************************************************************************\
    |                                          External View/Pure Functions                                            |
    \******************************************************************************************************************/


    function test_earnerRate() public 
    {

    }

    function test_hasOptedOutOfEarning() public 
    {

    }

    function test_isEarning() public 
    {

    }

    function test_protocol() public 
    {

    }

    function test_rateModel() public 
    {

    }

    function test_spogRegistrar() public 
    {

    }

    function test_totalEarningSupply() public 
    {

    }

    function test_totalNonEarningSupply() public 
    {

    }
}
