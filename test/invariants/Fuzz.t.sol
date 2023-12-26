// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { ContractHelper } from "../../lib/common/src/ContractHelper.sol";

import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import { MinterRateModel } from "../../src/MinterRateModel.sol";
import { EarnerRateModel } from "../../src/EarnerRateModel.sol";

import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";

import { MockSPOGRegistrar } from "../utils/Mocks.sol";
import { ProtocolHarness } from "../utils/ProtocolHarness.sol";
import { MTokenHarness } from "../utils/MTokenHarness.sol";

import { Invariants } from "./Invariants.sol";

contract FuzzTests is Test {
    address internal _minter1 = makeAddr("minter1");
    address internal _minter2 = makeAddr("minter2");
    address internal _earner1 = makeAddr("earner1");
    address internal _earner2 = makeAddr("earner2");

    MockSPOGRegistrar internal _spogRegistrar;
    MTokenHarness internal _mToken;
    ProtocolHarness internal _protocol;

    address internal _spogVault = makeAddr("spogVault");

    function setUp() external {
        _spogRegistrar = new MockSPOGRegistrar();
        _spogRegistrar.setVault(_spogVault);

        address deployer_ = makeAddr("deployer");
        address expectedProtocol_ = ContractHelper.getContractFrom(deployer_, 1);

        vm.startBroadcast(deployer_);

        _mToken = new MTokenHarness(address(_spogRegistrar), expectedProtocol_);
        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        vm.stopBroadcast();

        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.MINTER_RATE_MODEL,
            address(new MinterRateModel(address(_spogRegistrar)))
        );
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.EARNER_RATE_MODEL,
            address(new EarnerRateModel(address(_protocol)))
        );
        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter2);
        _spogRegistrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _earner1);

        _protocol.activateMinter(_minter1);
        _protocol.activateMinter(_minter2);
        _mToken.setIsEarning(_earner1, true);

        assertEq(_mToken.protocol(), address(_protocol));
        assertEq(_protocol.mToken(), address(_mToken));
    }

    function testFuzz_basic(
        uint256 minterRate,
        uint256 earnerRate,
        uint128 minterPrincipal,
        uint128 earnerPrincipal,
        uint256 timeElapsed
    ) external {
        minterRate = bound(minterRate, 100, 40000); // [0.1%, 400%] in basis points
        earnerRate = bound(earnerRate, 100, 40000); // [0.1%, 400%] in basis points
        minterPrincipal = uint128(bound(minterPrincipal, 1e6, type(uint128).max / 100));
        earnerPrincipal = uint128(bound(earnerPrincipal, 1e6, type(uint128).max / 100));
        timeElapsed = bound(timeElapsed, 10, 5 * 24 * 60 * 60); // [10, 5 days]

        vm.assume(earnerRate > minterRate);
        vm.assume(minterPrincipal >= earnerPrincipal);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, minterRate);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, earnerRate);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, minterPrincipal);
        _mToken.setInternalBalanceOf(_earner1, earnerPrincipal);
        _mToken.setTotalPrincipalOfEarningSupply(earnerPrincipal);
        _mToken.setIsEarning(_earner1, true);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant 1 failed");

        _protocol.updateIndex();

        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant 2 failed");

        vm.warp(block.timestamp + timeElapsed);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant 1 Failed.");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant 2 Failed.");

        vm.warp(block.timestamp + timeElapsed / 2);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, minterRate / 2);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, earnerRate * 2);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant 1 Failed.");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant 2 Failed.");

        vm.warp(block.timestamp + timeElapsed);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant 1 Failed.");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant 2 Failed.");
    }

    function testFuzz_removeMinter(
        uint256 minterRate,
        uint256 earnerRate,
        uint128 minterPrincipal1,
        uint128 minterPrincipal2,
        uint128 earnerPrincipal,
        uint256 timeElapsed
    ) external {
        minterPrincipal1 = uint128(bound(minterPrincipal1, 1e6, type(uint128).max / 100));
        minterPrincipal2 = uint128(bound(minterPrincipal2, 1e6, type(uint128).max / 100));
        earnerPrincipal = uint128(bound(earnerPrincipal, 1e6, type(uint128).max / 100));
        minterRate = bound(minterRate, 100, 40000); // 20%
        earnerRate = bound(earnerRate, 100, 40000); // 20%
        timeElapsed = bound(timeElapsed, 10 * 24 * 60 * 60, 30 * (24 * 60 * 60));

        vm.assume(earnerRate > minterRate);
        vm.assume(minterPrincipal1 + minterPrincipal2 >= earnerPrincipal);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, minterRate);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, earnerRate);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, minterPrincipal1);
        _protocol.setPrincipalOfActiveOwedMOf(_minter2, minterPrincipal2);

        _mToken.setTotalPrincipalOfEarningSupply(earnerPrincipal);
        _mToken.setInternalBalanceOf(_earner1, earnerPrincipal);
        _mToken.setIsEarning(_earner1, true);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant is not set 1");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant is not set 1");

        vm.warp(block.timestamp + timeElapsed);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant is not set 1.1");

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        IProtocol(_protocol).deactivateMinter(_minter1);

        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant is not set 2.1");

        vm.warp(block.timestamp + timeElapsed);

        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "Invariant is not set 2.2");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "Invariant is not set 3");
    }
}
