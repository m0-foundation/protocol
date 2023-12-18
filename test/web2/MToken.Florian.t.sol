// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test, Vm } from "../../lib/forge-std/src/Test.sol";
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
import { MTokenHarness } from "./util/MTokenHarness.sol";

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

    

    function test_burn() public {

    }

    function test_optOutOfEarning() public {

    }

    function test_startEarning() public 
    {
        vm.expectEmit(true, false, false, false, address(_mToken));
        emit IMToken.StartedEarning(_aliceAddress);
        _mToken.external_startEarning(_aliceAddress);

        assertTrue(_mToken.getter_isEarning(_aliceAddress));
    }

    function test_startEarning_alreadyEarning() public 
    { 
        _mToken.setter_isEarning(_aliceAddress, true);

        vm.expectRevert(IMToken.AlreadyEarning.selector);
        _mToken.external_startEarning(_aliceAddress);
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
