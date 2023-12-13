// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { MinterRateModel } from "../../src/MinterRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";

contract MinterRateTest is Test 
{
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    MinterRateModel internal _minterRateModel;
    uint256 _baseRate = 456;

    function setUp() public 
    {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.BASE_MINTER_RATE),
            abi.encode(_baseRate)
        );

        _minterRateModel = new MinterRateModel(_spogRegistrarAddress);
    }

    function test_setUp() public 
    {
        assertEq(_spogRegistrarAddress, _minterRateModel.spogRegistrar(), "Setup spogRegistrar address failed");
    }

    function test_baseRate() public 
    {
        assertEq(_baseRate, _minterRateModel.baseRate());
    }

    function test_rate() public 
    {
        assertEq(_baseRate, _minterRateModel.rate());
    }
}
