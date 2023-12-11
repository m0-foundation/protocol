// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { EarnerRateModel } from "../../src/EarnerRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";

contract EarnerRateTest is Test {

    address internal _protocolAddress = makeAddr("protocol");
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _mTokenAddress = makeAddr("mToken");
    EarnerRateModel internal _earnerRateModel; 

    function setUp() public {

        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IProtocol.spogRegistrar.selector),
            abi.encode(_spogRegistrarAddress)
        );

        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IProtocol.mToken.selector),
            abi.encode(_mTokenAddress)
        );

        _earnerRateModel = new EarnerRateModel(_protocolAddress);
    }

    function test_setUp() public {
        assertEq(_protocolAddress, _earnerRateModel.protocol(), "Setup protocol address failed");
        assertEq(_spogRegistrarAddress, _earnerRateModel.spogRegistrar(), "Setup spogRegistrar address failed");
        assertEq(_mTokenAddress, _earnerRateModel.mToken(), "Setup mToken address failed");
    }

    function test_rate_noTotalActiveOwedM() public {
        _setTotalActiveOwedM(0);
        assertEq(0, _earnerRateModel.rate());
    }

    // When no total earning supply is given, the base rate is taken 
    function test_rate_noTotalEarningSupply() public {
         _setTotalActiveOwedM(100);
         _setTotalEarningSupply(0);
         _setBaseRate(10); 

        assertEq(10, _earnerRateModel.rate());
    }



    // Case 1) baseRate * 10_000
    // Case 2) baseRate * utilization
    // Case 3) minterRate * utilization
    //
    // min( (baseRate * min(10_000, utilization)), minterRate * utilization)
    // a) (totalActiveOwedM * 10_000) / totalEarningSupply = utilization
    // b) min(10_000, a)
    // c) baseRate * b
    // d) minterRate * a / 10_0000
    // e) min(c, d)


    function test_rate_case_1() public {
         _setTotalActiveOwedM(100);
         _setTotalEarningSupply(200);
         _setBaseRate(10); 
         _setMinterRate(1000);

        // a: (100 * 10_000) / 200 = 5_000
        // b: min(5_000, 10_000) = 5_000
        // c: 10 * 5_000 = 50_000
        // d: 1_000 * 5_000  = 5_000_000 
        // e: min(50_000, 5_000_000) / 10_000 = 50_000

        assertEq(5, _earnerRateModel.rate());
    }

    function test_rate_case_2() public {
         _setTotalActiveOwedM(400);
         _setTotalEarningSupply(200);
         _setBaseRate(10); 
         _setMinterRate(1000);

        // a: (400 * 10_000) / 200 = 20_000
        // b: min(20_000, 10_000) = 10_000
        // c: 10 * 10_000 = 100_000
        // d: 1_000 * 20_000 = 20_000_000 
        // e: min(100_000, 20_000_000) / 10_000 = 10
        assertEq(10, _earnerRateModel.rate());
    }

    function test_rate_case_3() public {
         _setTotalActiveOwedM(400);
         _setTotalEarningSupply(200);
         _setBaseRate(10); 
         _setMinterRate(3);

        // a: (400 * 10_000) / 200 = 20_000
        // b: min(20_000, 10_000) = 10_000
        // c: 10 * 10_000 = 100_000
        // d: 3 * 20_000 = 60_000
        // e: min(100_000, 60_000) / 10_000 = 6
        assertEq(6, _earnerRateModel.rate());
    }

    function test_baseRate() public {
        uint256 expectedBaseRate = 123;

        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.BASE_EARNER_RATE),
            abi.encode(expectedBaseRate)
        ); 
        assertEq(expectedBaseRate,_earnerRateModel.baseRate());
    }

    // --- Helpers ----
    function _setTotalActiveOwedM(uint256 value) private
    {
        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IProtocol.totalActiveOwedM.selector),
            abi.encode(value)
        );
    }

    function _setTotalEarningSupply(uint256 value) private
    {
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IMToken.totalEarningSupply.selector),
            abi.encode(value)
        );
    }

    function _setBaseRate(uint256 value) private
    {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.BASE_EARNER_RATE),
            abi.encode(value)
        ); 
    }

    function _setMinterRate(uint256 value) private
    {
        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IProtocol.minterRate.selector),
            abi.encode(value)
        );
    }

}
