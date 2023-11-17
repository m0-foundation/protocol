// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";
import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

import { MockProtocol, MockSPOGRegistrar } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";

// TODO: Fuzz and/or invariant tests.

contract MTokenTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint256 internal _baseEarnerRate = ContinuousIndexingMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _minterRate = ContinuousIndexingMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _earnerRate = ContinuousIndexingMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _start = block.timestamp;

    uint256 internal _expectedCurrentIndex;

    MockProtocol internal _protocol;
    MockSPOGRegistrar internal _registrar;
    MTokenHarness internal _mToken;

    function setUp() external {
        _protocol = new MockProtocol();

        _protocol.setMinterRate(_minterRate);

        _registrar = new MockSPOGRegistrar();

        _registrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, _baseEarnerRate);

        _mToken = new MTokenHarness(address(_registrar), address(_protocol));

        _mToken.setLatestRate(_earnerRate);

        vm.warp(_start + 30_057_038); // Just enough time for the index to be ~1.1.

        _expectedCurrentIndex = 1_100_000_002_107_323_285;
    }

    function test_mint_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.mint(_alice, 0);
    }

    function test_mint_toNonEarner() external {
        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.internalBalanceOf(_alice), 1_000);
        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_mint_toEarner() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setIsEarning(_alice, true);

        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_burn_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientBalance_fromNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(_protocol));
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_insufficientBalance_fromEarner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(_protocol));
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_fromNonEarner() external {
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);
        assertEq(_mToken.totalNonEarningSupply(), 500);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_burn_fromEarner() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 455);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 1);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 1);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_transfer_insufficientBalance_fromNonEarner_toNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_fromNonEarner_toNonEarner() external {
        _mToken.setTotalNonEarningSupply(1_500);

        _mToken.setInternalBalanceOf(_alice, 1_000);
        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_500);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _protocol.setTotalActiveOwedM(1_500);

        _mToken.setTotalPrincipalOfEarningSupply(909);
        _mToken.setTotalNonEarningSupply(500);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 455);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _protocol.setTotalActiveOwedM(1_500);

        _mToken.setTotalPrincipalOfEarningSupply(455);
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalNonEarningSupply(), 500);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_transfer_fromEarner_toEarner() external {
        _protocol.setTotalActiveOwedM(1_500);

        _mToken.setTotalPrincipalOfEarningSupply(1_364);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 1_364);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_startEarning_onBehalfOf_notApprovedEarner() external {
        vm.expectRevert(IMToken.NotApprovedEarner.selector);
        _mToken.startEarning(_alice);
    }

    function test_startEarning_onBehalfOf_hasOptedOutOfEarning() external {
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        _mToken.setHasOptedOutOfEarning(_alice, true);

        vm.expectRevert(IMToken.HasOptedOut.selector);
        _mToken.startEarning(_alice);
    }

    function test_startEarning_onBehalfOf_alreadyEarning() external {
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);
        _mToken.setIsEarning(_alice, true);

        vm.expectRevert(IMToken.AlreadyEarning.selector);
        _mToken.startEarning(_alice);
    }

    function test_startEarning_onBehalfOf() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        _mToken.startEarning(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_startEarning_notApprovedEarner() external {
        vm.expectRevert(IMToken.NotApprovedEarner.selector);
        vm.prank(_alice);
        _mToken.startEarning();
    }

    function test_startEarning_alreadyEarning() external {
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);
        _mToken.setIsEarning(_alice, true);

        vm.expectRevert(IMToken.AlreadyEarning.selector);
        vm.prank(_alice);
        _mToken.startEarning();
    }

    function test_startEarning() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);
        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_stopEarning_onBehalfOf_isApprovedEarner() external {
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        vm.expectRevert(IMToken.IsApprovedEarner.selector);
        _mToken.stopEarning(_alice);
    }

    function test_stopEarning_onBehalfOf_alreadyNotEarning() external {
        vm.expectRevert(IMToken.AlreadyNotEarning.selector);
        _mToken.stopEarning(_alice);
    }

    function test_stopEarning_onBehalfOf() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.stopEarning(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_stopEarning_alreadyNotEarning() external {
        vm.expectRevert(IMToken.AlreadyNotEarning.selector);
        vm.prank(_alice);
        _mToken.stopEarning();
    }

    function test_stopEarning() external {
        _protocol.setTotalActiveOwedM(1_000);

        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_alice);
        _mToken.stopEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.hasOptedOutOfEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_updateIndex() external {
        _protocol.setTotalActiveOwedM(1_000);

        uint256 expectedLatestIndex_ = ContinuousIndexingMath.EXP_BASE_SCALE;
        uint256 expectedLatestUpdateTimestamp_ = _start;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = ContinuousIndexingMath.multiply(
            ContinuousIndexingMath.EXP_BASE_SCALE,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_earnerRate),
                block.timestamp - _start
            )
        );

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = block.timestamp;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _registrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, _baseEarnerRate / 2);

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate); // Has not changed yet.
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = ContinuousIndexingMath.multiply(
            _expectedCurrentIndex,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_earnerRate / 2),
                365 days
            )
        );

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = block.timestamp;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestEarnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);
    }

    function test_balanceOf_nonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.balanceOf(_alice), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_000); // Is not dependent on latestIndex.
    }

    function test_balanceOf_earner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        assertEq(_mToken.balanceOf(_alice), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.balanceOf(_alice), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_202); // Is dependent on latestIndex.
    }

    function test_totalEarningSupply() external {
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalEarningSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalEarningSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalEarningSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.totalEarningSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalNonEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalNonEarningSupply(), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000); // Is not dependent on latestIndex.
    }

    function test_totalSupply_noTotalEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalSupply(), 1_000);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestIndex.
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.totalSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalSupply(), 1_999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 2_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 2_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000_000_000);

        assertEq(_mToken.totalSupply(), 2_202); // Is dependent on latestIndex.
    }

    function test_earnerRate() external {
        assertEq(_mToken.earnerRate(), _earnerRate);

        // Set to arrive at an utilization of 200% (inverse utilization of 50%).
        _protocol.setTotalActiveOwedM(500);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.earnerRate(), _earnerRate / 2);
    }

    function test_latestEarnerRate() external {
        assertEq(_mToken.latestEarnerRate(), _earnerRate);

        _mToken.setLatestRate(_earnerRate / 2);

        assertEq(_mToken.latestEarnerRate(), _earnerRate / 2);
    }

    function test_optOutOfEarning() external {
        vm.prank(_alice);
        _mToken.optOutOfEarning();

        assertEq(_mToken.hasOptedOutOfEarning(_alice), true);
    }
}
