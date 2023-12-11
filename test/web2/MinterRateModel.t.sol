// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { MinterRateModel } from "../../src/MinterRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";

contract MinterRateTest is Test {

    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    MinterRateModel internal _minterRateModel; 

    function setUp() public {
        _minterRateModel = new MinterRateModel(_spogRegistrarAddress);
    }

    function test_setUp() public {
        assertEq(_spogRegistrarAddress, _minterRateModel.spogRegistrar(), "Setup spogRegistrar address failed");
    }


    function test_baseRate() public {
        uint256 expectedBaseRate = 123;
         _setBaseRate(expectedBaseRate);

        assertEq(expectedBaseRate,_minterRateModel.baseRate());
    }


    function test_rate() public {
        uint256 expectedBaseRate = 456;
        _setBaseRate(expectedBaseRate);
        
        assertEq(expectedBaseRate,_minterRateModel.rate());
    }

    // Helper
    function _setBaseRate(uint256 value) private
    {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.BASE_MINTER_RATE),
            abi.encode(value)
        ); 
    }

}
