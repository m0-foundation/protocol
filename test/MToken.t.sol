// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";
import { InterestMath } from "../src/libs/InterestMath.sol";

import { MockSPOGRegistrar, MockRateModel } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";

// TODO: Fuzz and/or invariant tests.

contract MTokenTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");
    address internal _protocol = makeAddr("protocol");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint256 internal _rate = InterestMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _start = block.timestamp;

    uint256 internal _expectedCurrentIndex;

    MTokenHarness internal _mToken;
    MockSPOGRegistrar internal _registrar;
    MockRateModel internal _rateModel;

    function setUp() external {
        _registrar = new MockSPOGRegistrar();
        _rateModel = new MockRateModel();
        _mToken = new MTokenHarness(address(_protocol), address(_registrar));

        _registrar.updateConfig(
            SPOGRegistrarReader.EARNER_RATE_MODEL,
            SPOGRegistrarReader.toBytes32(address(_rateModel))
        );

        _rateModel.setRate(_rate);

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
        assertEq(_mToken.internalTotalSupply(), 1_000);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), InterestMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestAccrualTime(), _start);
    }

    function test_mint_toEarner() external {
        _mToken.setIsEarning(_alice, true);

        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
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
        _mToken.setInternalTotalSupply(1_000);
        _mToken.setInternalBalanceOf(_alice, 1_000);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);
        assertEq(_mToken.internalTotalSupply(), 500);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), InterestMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestAccrualTime(), _start);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), InterestMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestAccrualTime(), _start);
    }

    function test_burn_fromEarner() external {
        _mToken.setTotalEarningSupplyPrincipal(909);
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);
        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 455);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 1);
        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 1);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
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
        _mToken.setInternalTotalSupply(1_500);
        _mToken.setInternalBalanceOf(_alice, 1_000);
        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.internalTotalSupply(), 1_500);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), InterestMath.EXP_BASE_SCALE);
        assertEq(_mToken.latestAccrualTime(), _start);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _mToken.setTotalEarningSupplyPrincipal(909);
        _mToken.setInternalTotalSupply(500);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.internalTotalSupply(), 1_000);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 455);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _mToken.setTotalEarningSupplyPrincipal(455);
        _mToken.setInternalTotalSupply(1000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.internalTotalSupply(), 500);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setTotalEarningSupplyPrincipal(1364);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 1364);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_startEarning_onBehalfOf_notApprovedEarner() external {
        vm.expectRevert(IMToken.NotApprovedEarner.selector);
        _mToken.startEarning(_alice);
    }

    function test_startEarning_onBehalfOf_hasOptedOut() external {
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        _mToken.setHasOptedOut(_alice, true);

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
        _mToken.setInternalBalanceOf(_alice, 1_000);
        _mToken.setInternalTotalSupply(1_000);

        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        _mToken.startEarning(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
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
        _mToken.setInternalBalanceOf(_alice, 1_000);
        _mToken.setInternalTotalSupply(1_000);

        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);
        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
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
        _mToken.setTotalEarningSupplyPrincipal(909);
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.stopEarning(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);

        assertEq(_mToken.internalTotalSupply(), 999);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_stopEarning_alreadyNotEarning() external {
        vm.expectRevert(IMToken.AlreadyNotEarning.selector);
        vm.prank(_alice);
        _mToken.stopEarning();
    }

    function test_stopEarning() external {
        _mToken.setTotalEarningSupplyPrincipal(909);
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_alice);
        _mToken.stopEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.hasOptedOutOfEarning(_alice), true);

        assertEq(_mToken.internalTotalSupply(), 999);
        assertEq(_mToken.totalEarningSupplyPrincipal(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_updateIndex() external {
        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestIndex(), InterestMath.EXP_BASE_SCALE);

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = InterestMath.multiply(
            InterestMath.EXP_BASE_SCALE,
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(_rate), block.timestamp - _start)
        );

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);

        _mToken.updateIndex();

        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex); // Has not changed yet.

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = InterestMath.multiply(
            _expectedCurrentIndex,
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(_rate), 365 days)
        );

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);

        _mToken.updateIndex();

        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestAccrualTime(), block.timestamp);
    }

    function test_balanceOf_nonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_000);
    }

    function test_balanceOf_earner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        assertEq(_mToken.balanceOf(_alice), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_105);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        // Note that unrealized earnings are subject to change for any period before the last index update.
        assertEq(_mToken.balanceOf(_alice), 1_002);
    }

    function test_totalEarningSupply() external {
        _mToken.setTotalEarningSupplyPrincipal(909);

        assertEq(_mToken.totalEarningSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalEarningSupply(), 1_105);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        // Note that unrealized earnings are subject to change for any period before the last index update.
        assertEq(_mToken.totalEarningSupply(), 1_002);
    }

    function test_totalSupply_noTotalEarningSupply() external {
        _mToken.setInternalTotalSupply(1_000);

        assertEq(_mToken.totalSupply(), 1_000);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_000);
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _mToken.setTotalEarningSupplyPrincipal(909);

        assertEq(_mToken.totalSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_105);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        // Note that unrealized earnings are subject to change for any period before the last index update.
        assertEq(_mToken.totalSupply(), 1_002);
    }

    function test_totalSupply() external {
        _mToken.setInternalTotalSupply(1_000);
        _mToken.setTotalEarningSupplyPrincipal(909);

        assertEq(_mToken.totalSupply(), 1_999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 2_105);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        // Note that unrealized earnings are subject to change for any period before the last index update.
        assertEq(_mToken.totalSupply(), 2_002);
    }

    function test_earningRate() external {
        assertEq(_mToken.earningRate(), _rate);

        _rateModel.setRate(_rate = InterestMath.BPS_BASE_SCALE / 20); // 5% APY

        assertEq(_mToken.earningRate(), _rate);
    }

    function test_optOutOfEarning() external {
        vm.prank(_alice);
        _mToken.optOutOfEarning();

        assertEq(_mToken.hasOptedOutOfEarning(_alice), true);
    }
}
