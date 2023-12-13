// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { EarnerRateModel } from "../../src/EarnerRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";

contract EarnerRateModelTest is Test 
{
    address internal _protocolAddress = makeAddr("protocol");
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _mTokenAddress = makeAddr("mToken");
    EarnerRateModel internal _earnerRateModel; 

    function setUp() public 
    {
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

    function test_setUp() public 
    {
        assertEq(_protocolAddress, _earnerRateModel.protocol(), "Setup protocol address failed");
        assertEq(_spogRegistrarAddress, _earnerRateModel.spogRegistrar(), "Setup spogRegistrar address failed");
        assertEq(_mTokenAddress, _earnerRateModel.mToken(), "Setup mToken address failed");
    }

    function test_rate_noTotalActiveOwedM() public 
    {
        _setTotalActiveOwedM(0);
        assertEq(0, _earnerRateModel.rate());
    }

    // When no total earning supply is given, the base rate is taken 
    function test_rate_noTotalEarningSupply() public 
    {
        _setTotalActiveOwedM(100);
        _setTotalEarningSupply(0);
        _setBaseEarnerRate(10); 

        assertEq(10, _earnerRateModel.rate());
    }

    // Case 1) baseRate * 10_000
    // Case 2) baseRate * utilization
    // Case 3) minterRate * utilization
    // Case 4) maximum values
    //
    // rate(): 
    // return: min( (baseRate * min(10_000, utilization)), minterRate * utilization) / 10_000
    //                   
    // a) (totalActiveOwedM * 10_000) / totalEarningSupply = utilization
    // b) min(10_000, a)
    // c) baseRate * b
    // d) minterRate * a
    // e) min(c, d) / 10_0000
    function test_rate_case_1() public 
    {
        // a: (100 * 10_000) / 200 = 5_000 (utilization)
        _setTotalActiveOwedM(100);
        _setTotalEarningSupply(200);
        
        // b: min(10_000, 5_000) = 5_000 
        // c: 10 * 5_000 (b) = 50_000
        _setBaseEarnerRate(10);

        // d: 1_000 * 5_000 = 5_000_000
        _setMinterRate(1000);

        // e: min(50_000, 5_000_000) / 10_000 = 5
        assertEq(5, _earnerRateModel.rate());
    }

    function test_rate_case_2() public 
    {
        // a: (400 * 10_000) / 200 = 20_000 (utilization)
        _setTotalActiveOwedM(400);
        _setTotalEarningSupply(200);

        // b: min(10_000, 20_000) = 10_000
        // c: 10 * 10_000 = 100_000
        _setBaseEarnerRate(10);

        // d: 1_000 * 20_000 = 20_000_000 
        _setMinterRate(1000);

        // e: min(100_000, 20_000_000) / 10_000 = 10
        assertEq(10, _earnerRateModel.rate());
    }

    function test_rate_case_3() public 
    {
        // a: (400 * 10_000) / 200 = 20_000 (utilization)
        _setTotalActiveOwedM(400);
        _setTotalEarningSupply(200);

        // b: min(10_000, 20_000) = 10_000
        // c: 10 * 10_000 = 100_000
        _setBaseEarnerRate(10); 

        // d: 3 * 20_000 = 60_000
        _setMinterRate(3);

        // e: min(100_000, 60_000) / 10_000 = 6
        assertEq(6, _earnerRateModel.rate());
    }

    function test_rate_case_4() public 
    {
        // a: (uint256.max) / 1 = uint256.max (utilization)
        _setTotalActiveOwedM(type(uint256).max / 10000);
        _setTotalEarningSupply(1);

        // b: min(10_000, uint256.max) = 10_000
        // c: (uint256.max / 10_000) * 10_000 = uint256.max
        _setBaseEarnerRate(type(uint256).max / 10000); 

        // d: 1 * uint256.max = uint256.max
        _setMinterRate(1);

        // e: min(uint256.max, uint256.max) / 10_000
        assertEq(type(uint256).max / 10000, _earnerRateModel.rate());
    }

    function test_baseRate() public 
    {
        uint256 expectedBaseRate = 123;
        _setBaseEarnerRate(expectedBaseRate);

        assertEq(expectedBaseRate, _earnerRateModel.baseRate());
    }

    function test_rateFallbackBaseRate() public 
    {
        uint256 expectedRate = 1111;
        _setTotalActiveOwedM(100);
        _setTotalEarningSupply(0); // base rate has to be used
        _setBaseEarnerRate(expectedRate);
        _setMinterRate(1000);

        assertEq(expectedRate, _earnerRateModel.rate());
    }

    // Test for Boundary Values
    function test_baseRateMax() public 
    {
        uint256 maxUint = type(uint256).max;
        _setBaseEarnerRate(maxUint);

        assertEq(maxUint, _earnerRateModel.baseRate());
    }

    // Test for Zero Minter Rate
    // Ensure that the contract behaves as expected when the minter rate is zero.
    function test_rate_zeroMinterRate() public {
        _setTotalActiveOwedM(100);
        _setTotalEarningSupply(200);
        _setBaseEarnerRate(10);
        _setMinterRate(0); // zero minter rate

        assertEq(0, _earnerRateModel.rate());
    }

    // Test for Extremely High Rate Values
    function test_rate_highBaseAndMinterRates() public {
        uint256 highRate = 10**18; // An extremely high rate
        _setTotalActiveOwedM(100);
        _setTotalEarningSupply(200);
        _setBaseEarnerRate(highRate);
        _setMinterRate(highRate);

        assertEq(500000000000000000, _earnerRateModel.rate());
    }

    // Fuzz Testing
    function test_rate_fuzz(
        uint256 totalActiveOwedM, 
        uint256 totalEarningSupply, 
        uint256 baseEarnerRate, 
        uint256 minterRate) public 
    {
        // only if ... 
        // because these values would return directly 0 or baseRate()
        vm.assume(totalActiveOwedM > 0);
        vm.assume(totalEarningSupply > 0);

        // overflow protection
        vm.assume(totalActiveOwedM <= type(uint256).max / 10_000);
        vm.assume(baseEarnerRate   <= type(uint256).max / 10_000);
        vm.assume(minterRate       <= type(uint256).max / 10_000);

        _setTotalActiveOwedM(totalActiveOwedM);
        _setTotalEarningSupply(totalEarningSupply);
        _setBaseEarnerRate(baseEarnerRate);
        _setMinterRate(minterRate);

        uint256 utilization = (totalActiveOwedM * 10_000) / totalEarningSupply;
        uint256 utilizationMax10000 = (utilization < 10000) ? utilization : 10000;
        uint256 c = baseEarnerRate * utilizationMax10000; // todo: naming
        
        // overflow protection
        vm.assume(minterRate  <= type(uint128).max);
        vm.assume(utilization <= type(uint128).max);

        uint256 d = minterRate * utilization; // todo: naming
        uint256 min2 = (c < d) ? c : d; // todo: naming
        uint256 calculatedRate = min2 / 10000;

        assertEq(baseEarnerRate, _earnerRateModel.baseRate());
        assertEq(calculatedRate, _earnerRateModel.rate());
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

    function _setBaseEarnerRate(uint256 value) private
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
