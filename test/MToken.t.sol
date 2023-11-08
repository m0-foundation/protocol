// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";
import { InterestMath } from "../src/libs/InterestMath.sol";

import { MockSPOGRegistrar, MockRateModel } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";

contract MTokenTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    address internal _protocol = makeAddr("protocol");

    MTokenHarness internal _mToken;
    MockSPOGRegistrar internal _registrar;
    MockRateModel internal _rateModel;

    function setUp() external {
        _registrar = new MockSPOGRegistrar();
        _rateModel = new MockRateModel();
        _mToken = new MTokenHarness(address(_protocol), address(_registrar));

        _registrar.updateConfig(
            SPOGRegistrarReader.INTEREST_RATE_MODEL,
            SPOGRegistrarReader.toBytes32(address(_rateModel))
        );
    }

    function test_mint_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.mint(_alice, 0);
    }

    function test_mint_toNonInterestEarner() external {
        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);
        assertEq(_mToken.internalBalanceOf(_alice), 1_000);
        assertEq(_mToken.totalSupply(), 1_000);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 1_000);
    }

    function test_mint_toInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setIsEarningInterest(_alice, true);

        vm.prank(address(_protocol));
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 999);
        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalSupply(), 999);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 0);
    }

    function test_burn_notProtocol() external {
        vm.expectRevert(IMToken.NotProtocol.selector);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientBalance_fromNonInterestEarner() external {
        _mToken.setInternalBalance(_alice, 999);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(_protocol));
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_insufficientBalance_fromInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 908);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(_protocol));
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_fromNonInterestEarner() external {
        _mToken.setInternalTotalSupply(1_000);
        _mToken.setInternalBalance(_alice, 1_000);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 500);
        assertEq(_mToken.totalSupply(), 500);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 500);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalSupply(), 0);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 0);
    }

    function test_burn_fromInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(909);
        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 455);
        assertEq(_mToken.totalSupply(), 500);
        assertEq(_mToken.interestEarningTotalSupply(), 455);
        assertEq(_mToken.internalTotalSupply(), 0);

        vm.prank(address(_protocol));
        _mToken.burn(_alice, 500);

        assertEq(_mToken.balanceOf(_alice), 1);
        assertEq(_mToken.internalBalanceOf(_alice), 1);
        assertEq(_mToken.totalSupply(), 1);
        assertEq(_mToken.interestEarningTotalSupply(), 1);
        assertEq(_mToken.internalTotalSupply(), 0);
    }

    function test_transfer_insufficientBalance_fromNonInterestEarner_toNonInterestEarner() external {
        _mToken.setInternalBalance(_alice, 999);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromInterestEarner_toNonInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 908);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_fromNonInterestEarner_toNonInterestEarner() external {
        _mToken.setInternalTotalSupply(1_500);
        _mToken.setInternalBalance(_alice, 1_000);
        _mToken.setInternalBalance(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 1_500);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 1_500);
    }

    function test_transfer_fromInterestEarner_toNonInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(909);
        _mToken.setInternalTotalSupply(500);

        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        _mToken.setInternalBalance(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 1_500);
        assertEq(_mToken.interestEarningTotalSupply(), 455);
        assertEq(_mToken.internalTotalSupply(), 1_000);
    }

    function test_transfer_fromNonInterestEarner_toInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(455);
        _mToken.setInternalTotalSupply(1000);

        _mToken.setInternalBalance(_alice, 1_000);

        _mToken.setIsEarningInterest(_bob, true);
        _mToken.setInternalBalance(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.balanceOf(_bob), 999);
        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalSupply(), 1_499);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 500);
    }

    function test_transfer_fromInterestEarner_toInterestEarner() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(1364);

        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        _mToken.setIsEarningInterest(_bob, true);
        _mToken.setInternalBalance(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.balanceOf(_alice), 500);
        assertEq(_mToken.internalBalanceOf(_alice), 455);

        assertEq(_mToken.balanceOf(_bob), 999);
        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalSupply(), 1_500);
        assertEq(_mToken.interestEarningTotalSupply(), 1364);
        assertEq(_mToken.internalTotalSupply(), 0);
    }

    function test_startEarningInterest_notApprovedInterestEarner() external {
        vm.expectRevert(IMToken.NotApprovedInterestEarner.selector);
        vm.prank(_alice);
        _mToken.startEarningInterest();
    }

    function test_startEarningInterest_alreadyEarningInterest() external {
        _registrar.addToList(SPOGRegistrarReader.INTEREST_EARNERS_LIST, _alice);
        _mToken.setIsEarningInterest(_alice, true);

        vm.expectRevert(IMToken.AlreadyEarningInterest.selector);
        vm.prank(_alice);
        _mToken.startEarningInterest();
    }

    function test_startEarningInterest() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInternalBalance(_alice, 1_000);
        _mToken.setInternalTotalSupply(1_000);

        _registrar.addToList(SPOGRegistrarReader.INTEREST_EARNERS_LIST, _alice);

        vm.prank(_alice);
        _mToken.startEarningInterest();

        assertEq(_mToken.balanceOf(_alice), 999);
        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalSupply(), 999);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 0);
        assertEq(_mToken.isEarningInterest(_alice), true);
    }

    function test_stopEarningInterest_onBehalfOf_isApprovedInterestEarner() external {
        _registrar.addToList(SPOGRegistrarReader.INTEREST_EARNERS_LIST, _alice);

        vm.expectRevert(IMToken.IsApprovedInterestEarner.selector);
        _mToken.stopEarningInterest(_alice);
    }

    function test_stopEarningInterest_onBehalfOf_alreadyNotEarningInterest() external {
        vm.expectRevert(IMToken.AlreadyNotEarningInterest.selector);
        _mToken.stopEarningInterest(_alice);
    }

    function test_stopEarningInterest_onBehalfOf() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(909);
        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        _mToken.stopEarningInterest(_alice);

        assertEq(_mToken.balanceOf(_alice), 999);
        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.totalSupply(), 999);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 999);
        assertEq(_mToken.isEarningInterest(_alice), false);
    }

    function test_stopEarningInterest_alreadyNotEarningInterest() external {
        vm.expectRevert(IMToken.AlreadyNotEarningInterest.selector);
        vm.prank(_alice);
        _mToken.stopEarningInterest();
    }

    function test_stopEarningInterest() external {
        _mToken.setInterestIndex(InterestMath.EXP_BASE_SCALE + InterestMath.EXP_BASE_SCALE / 10); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(909);
        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        vm.prank(_alice);
        _mToken.stopEarningInterest();

        assertEq(_mToken.balanceOf(_alice), 999);
        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.totalSupply(), 999);
        assertEq(_mToken.interestEarningTotalSupply(), 0);
        assertEq(_mToken.internalTotalSupply(), 999);
        assertEq(_mToken.isEarningInterest(_alice), false);
    }

    function test_earningInterest() external {
        uint256 apy_ = InterestMath.BPS_BASE_SCALE / 10; // 10% APY
        uint256 start_ = block.timestamp;
        uint256 currentInterestIndex_ = InterestMath.EXP_BASE_SCALE + InterestMath.convertFromBasisPoints(apy_);

        _rateModel.setRate(apy_);

        _mToken.setInterestIndex(currentInterestIndex_); // 10% interest index.
        _mToken.setInterestEarningTotalSupply(909);
        _mToken.setInternalTotalSupply(1000);

        _mToken.setIsEarningInterest(_alice, true);
        _mToken.setInternalBalance(_alice, 909);

        _mToken.setInternalBalance(_bob, 1000);

        assertEq(_mToken.currentInterestIndex(), currentInterestIndex_);
        assertEq(_mToken.interestIndex(), currentInterestIndex_);

        vm.warp(start_ + 365 days);

        currentInterestIndex_ = InterestMath.multiply(
            currentInterestIndex_,
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(apy_), 365 days)
        );

        assertEq(_mToken.currentInterestIndex(), currentInterestIndex_);

        assertEq(_mToken.balanceOf(_alice), 1_105);
        assertEq(_mToken.internalBalanceOf(_alice), 909);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 2_105);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 1_000);

        _mToken.updateInterestIndex();

        assertEq(_mToken.interestIndex(), currentInterestIndex_);

        assertEq(_mToken.balanceOf(_alice), 1_105);
        assertEq(_mToken.internalBalanceOf(_alice), 909);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 2_105);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 1_000);

        apy_ = InterestMath.BPS_BASE_SCALE / 20; // 5% APY

        _rateModel.setRate(apy_);

        assertEq(_mToken.currentInterestIndex(), currentInterestIndex_); // Has not changed yet.

        vm.warp(start_ + 2 * 365 days);

        currentInterestIndex_ = InterestMath.multiply(
            currentInterestIndex_,
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(apy_), 365 days)
        );

        assertEq(_mToken.currentInterestIndex(), currentInterestIndex_);

        assertEq(_mToken.balanceOf(_alice), 1_161);
        assertEq(_mToken.internalBalanceOf(_alice), 909);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 2_161);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 1_000);

        _mToken.updateInterestIndex();

        assertEq(_mToken.interestIndex(), currentInterestIndex_);

        assertEq(_mToken.balanceOf(_alice), 1_161);
        assertEq(_mToken.internalBalanceOf(_alice), 909);

        assertEq(_mToken.balanceOf(_bob), 1_000);
        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalSupply(), 2_161);
        assertEq(_mToken.interestEarningTotalSupply(), 909);
        assertEq(_mToken.internalTotalSupply(), 1_000);
    }
}
