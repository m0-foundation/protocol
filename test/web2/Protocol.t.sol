// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { Protocol } from "../../src/Protocol.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { MockMToken }  from "./mock/MockMToken.sol";
import { MockSPOGRegistrar }  from "./mock/MockSPOGRegistrar.sol";

import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";



contract ProtocolTest is Test {
    uint256 testNumber;

    MockSPOGRegistrar _registrar;
    MockMToken _mToken;
    IProtocol _protocol;

    address internal _vault = makeAddr("vault");
    address internal _rateModel = makeAddr("rateModel");

    function setUp() public {
        testNumber = 42;

        _registrar = new MockSPOGRegistrar();
        _registrar.setVault(_vault);
        _mToken = new MockMToken();
        _protocol = new Protocol(address(_registrar), address(_mToken));

        _mToken.__setProtocol(address(_protocol));
        _mToken.__setRateModel(_rateModel);
        _mToken.__setSpogRegistrar(address(_registrar));
    }

    function test_NumberIs42() public {
        assertEq(testNumber, 42);
    }

    function testFail_Subtract43() public {
        testNumber -= 43;
    }


}
