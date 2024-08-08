// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IERC20Extended } from "../lib/common/src/interfaces/IERC20Extended.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { RegistrarReader } from "../src/libs/RegistrarReader.sol";

import { MockRegistrar } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";
import { TestUtils } from "./utils/TestUtils.sol";

// TODO: Test mint with increased index.
// TODO: Test update index.

contract MTokenTests is TestUtils {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");

    address internal _portal = makeAddr("portal");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint256 internal _start = vm.getBlockTimestamp();

    uint128 internal _expectedCurrentIndex;

    MockRegistrar internal _registrar;
    MTokenHarness internal _mToken;

    function setUp() external {
        _registrar = new MockRegistrar();
        _registrar.setPortal(_portal);

        _mToken = new MTokenHarness(address(_registrar));

        _mToken.setLatestIndex(_expectedCurrentIndex = 1_100000068703);
    }

    /* ============ initial state ============ */
    function test_initialState() external {
        assertEq(_mToken.registrar(), address(_registrar));
        assertEq(_mToken.portal(), _portal);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    /* ============ constructor ============ */
    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(IMToken.ZeroRegistrar.selector);
        new MTokenHarness(address(0));
    }

    function test_constructor_zeroPortal() external {
        _registrar.setPortal(address(0));

        vm.expectRevert(IMToken.ZeroPortal.selector);
        new MTokenHarness(address(_registrar));
    }

    /* ============ mint ============ */
    function test_mint_notPortal() external {
        vm.expectRevert(IMToken.NotPortal.selector);
        _mToken.mint(_alice, 0, 0);
    }

    function test_mint_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_portal);
        _mToken.mint(_alice, 0, 0);
    }

    function test_mint_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_portal);
        _mToken.mint(address(0), 1_000, 0);
    }

    function test_mint_toNonEarner() external {
        vm.prank(_portal);
        _mToken.mint(_alice, 1_000, 0);

        assertEq(_mToken.internalBalanceOf(_alice), 1_000);
        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_mint_toNonEarner(uint256 amount_) external {
        amount_ = bound(amount_, 1, type(uint112).max);

        vm.prank(_portal);
        _mToken.mint(_alice, amount_, 0);

        assertEq(_mToken.internalBalanceOf(_alice), amount_);
        assertEq(_mToken.totalNonEarningSupply(), amount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_mint_toNonEarner_overflowPrincipalOfTotalSupply() external {
        _mToken.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_portal);
        _mToken.mint(_alice, type(uint112).max - 1, 0);

        vm.prank(_portal);
        vm.expectRevert(IMToken.OverflowsPrincipalOfTotalSupply.selector);
        _mToken.mint(_bob, 2, 0);
    }

    function test_mint_toEarner() external {
        _mToken.setIsEarning(_alice, true);

        vm.prank(_portal);
        _mToken.mint(_alice, 999, 0);

        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.mint(_alice, 1, 0);

        // No change due to principal round down on mint.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.mint(_alice, 2, 0);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_mint_toEarner(uint256 amount_) external {
        amount_ = bound(amount_, 1, type(uint112).max);

        _mToken.setIsEarning(_alice, true);

        vm.prank(_portal);
        _mToken.mint(_alice, amount_, 0);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(amount_), _expectedCurrentIndex);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.mint(_alice, 1, 0);

        expectedPrincipalBalance_ += _getPrincipalAmountRoundedDown(uint240(1), _expectedCurrentIndex);

        // No change due to principal round down on mint.
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.mint(_alice, 2, 0);

        expectedPrincipalBalance_ += _getPrincipalAmountRoundedDown(uint240(2), _expectedCurrentIndex);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_mint_toEarner_overflowPrincipalOfTotalSupply() external {
        _mToken.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE);
        _mToken.setIsEarning(_alice, true);

        vm.expectRevert(IMToken.OverflowsPrincipalOfTotalSupply.selector);
        vm.prank(_portal);
        _mToken.mint(_alice, type(uint112).max, 0);
    }

    /* ============ burn ============ */
    function test_burn_notPortal() external {
        vm.expectRevert(IMToken.NotPortal.selector);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));
        vm.prank(_portal);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientBalance_fromNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_portal);
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_insufficientBalance_fromEarner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 908, 910));
        vm.prank(_portal);
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_fromNonEarner() external {
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        vm.prank(_portal);
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);
        assertEq(_mToken.totalNonEarningSupply(), 500);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_burn_fromNonEarner(uint256 supply_) external {
        supply_ = bound(supply_, 2, type(uint112).max);
        vm.assume(supply_ % 2 == 0);

        _mToken.setTotalNonEarningSupply(supply_);
        _mToken.setInternalBalanceOf(_alice, supply_);

        vm.prank(_portal);
        _mToken.burn(_alice, supply_ / 2);

        assertEq(_mToken.internalBalanceOf(_alice), supply_ / 2);
        assertEq(_mToken.totalNonEarningSupply(), supply_ / 2);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.burn(_alice, supply_ / 2);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_burn_fromEarner() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_portal);
        _mToken.burn(_alice, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_portal);
        _mToken.burn(_alice, 998);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_burn_fromEarner(uint256 amount_) external {
        amount_ = bound(amount_, 2, type(uint112).max);
        vm.assume(amount_ % 2 == 0);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(amount_), _expectedCurrentIndex);

        _mToken.setPrincipalOfTotalEarningSupply(expectedPrincipalBalance_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, expectedPrincipalBalance_);

        uint256 burnAmount_ = _mToken.balanceOf(_alice) / 2;
        vm.assume(burnAmount_ != 0);

        vm.prank(_portal);
        _mToken.burn(_alice, burnAmount_);

        expectedPrincipalBalance_ -= _getPrincipalAmountRoundedUp(uint240(burnAmount_), _expectedCurrentIndex);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        uint256 balanceOfAlice_ = _mToken.balanceOf(_alice);

        assertEq(
            _mToken.balanceOf(_alice),
            _getPresentAmountRoundedDown(uint112(expectedPrincipalBalance_), _expectedCurrentIndex)
        );

        vm.prank(_portal);
        _mToken.burn(_alice, balanceOfAlice_);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    /* ============ transfer ============ */
    function test_transfer_invalidRecipient() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_alice);
        _mToken.transfer(address(0), 1_000);
    }

    function test_transfer_insufficientBalance_fromNonEarner_toNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 908, 910));
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
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_fromNonEarner_toNonEarner(
        uint256 supply_,
        uint256 aliceBalance_,
        uint256 transferAmount_
    ) external {
        supply_ = bound(supply_, 1, type(uint112).max);
        aliceBalance_ = bound(aliceBalance_, 1, supply_);
        transferAmount_ = bound(transferAmount_, 1, aliceBalance_);
        uint256 bobBalance = supply_ - aliceBalance_;

        _mToken.setTotalNonEarningSupply(supply_);

        _mToken.setInternalBalanceOf(_alice, aliceBalance_);
        _mToken.setInternalBalanceOf(_bob, bobBalance);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(_mToken.internalBalanceOf(_alice), aliceBalance_ - transferAmount_);
        assertEq(_mToken.internalBalanceOf(_bob), bobBalance + transferAmount_);

        assertEq(_mToken.totalNonEarningSupply(), supply_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);
        _mToken.setTotalNonEarningSupply(500);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 454);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.principalOfTotalEarningSupply(), 454);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_alice);
        _mToken.transfer(_bob, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 453);

        assertEq(_mToken.internalBalanceOf(_bob), 1_001);

        assertEq(_mToken.totalNonEarningSupply(), 1_001);
        assertEq(_mToken.principalOfTotalEarningSupply(), 453);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_fromEarner_toNonEarner(
        uint256 amountEarning_,
        uint256 nonEarningSupply_,
        uint256 transferAmount_
    ) external {
        amountEarning_ = bound(amountEarning_, 2, type(uint112).max);
        transferAmount_ = bound(transferAmount_, 1, amountEarning_);
        nonEarningSupply_ = bound(nonEarningSupply_, 1, type(uint112).max);

        _mToken.setPrincipalOfTotalEarningSupply(amountEarning_);
        _mToken.setTotalNonEarningSupply(nonEarningSupply_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, amountEarning_);

        _mToken.setInternalBalanceOf(_bob, nonEarningSupply_);

        uint256 expectedPrincipalBalance_ = amountEarning_ -
            _getPrincipalAmountRoundedUp(uint240(transferAmount_), _expectedCurrentIndex);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.internalBalanceOf(_bob), nonEarningSupply_ + transferAmount_);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ + transferAmount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.assume(_mToken.balanceOf(_alice) != 0);

        vm.prank(_alice);
        _mToken.transfer(_bob, 1);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_ - 1);
        assertEq(_mToken.internalBalanceOf(_bob), nonEarningSupply_ + transferAmount_ + 1);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ + transferAmount_ + 1);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_ - 1);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toNonEarner_noOverflow() external {
        // Earner balances being capped to type(uint112).max
        // and non earners ones to type(uint240).max,
        // it is not possible to overflow the non earning balances
        // since the earning balances will always be lower.
        uint256 aliceBalance_ = type(uint112).max;
        uint256 bobBalance_ = 2;

        _mToken.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE);

        _mToken.setPrincipalOfTotalEarningSupply(aliceBalance_);
        _mToken.setTotalNonEarningSupply(bobBalance_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, aliceBalance_);

        _mToken.setInternalBalanceOf(_bob, bobBalance_);

        vm.prank(_alice);
        _mToken.transfer(_bob, aliceBalance_);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(_bob), aliceBalance_ + bobBalance_);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _mToken.setPrincipalOfTotalEarningSupply(455);
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 455);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalNonEarningSupply(), 500);
        assertEq(_mToken.principalOfTotalEarningSupply(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_fromNonEarner_toEarner(
        uint256 earningSupply_,
        uint256 nonEarningSupply_,
        uint256 transferAmount_
    ) external {
        earningSupply_ = bound(earningSupply_, 1, type(uint112).max / 2);
        nonEarningSupply_ = bound(nonEarningSupply_, 1, type(uint112).max / 2);
        transferAmount_ = bound(transferAmount_, 1, nonEarningSupply_);

        _mToken.setPrincipalOfTotalEarningSupply(earningSupply_);
        _mToken.setTotalNonEarningSupply(nonEarningSupply_);

        _mToken.setInternalBalanceOf(_alice, nonEarningSupply_);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, earningSupply_);

        uint256 expectedPrincipalBalance_ = earningSupply_ +
            _getPrincipalAmountRoundedDown(uint240(transferAmount_), _expectedCurrentIndex);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(_mToken.internalBalanceOf(_alice), nonEarningSupply_ - transferAmount_);

        assertEq(_mToken.internalBalanceOf(_bob), expectedPrincipalBalance_);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ - transferAmount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setPrincipalOfTotalEarningSupply(1_364);
        _mToken.setPrincipalOfTotalEarningSupply(1_364);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 454);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 454);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 1_364);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_fromEarner_toEarner(
        uint256 aliceBalance_,
        uint256 bobBalance_,
        uint256 transferAmount_
    ) external {
        aliceBalance_ = bound(aliceBalance_, 1, type(uint112).max / 2);
        bobBalance_ = bound(bobBalance_, 1, type(uint112).max / 2);
        transferAmount_ = bound(transferAmount_, 1, aliceBalance_);

        _mToken.setPrincipalOfTotalEarningSupply(aliceBalance_ + bobBalance_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, aliceBalance_);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, bobBalance_);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(
            _mToken.internalBalanceOf(_alice),
            aliceBalance_ - _getPrincipalAmountRoundedUp(uint240(transferAmount_), _expectedCurrentIndex)
        );

        assertEq(
            _mToken.internalBalanceOf(_bob),
            bobBalance_ + _getPrincipalAmountRoundedUp(uint240(transferAmount_), _expectedCurrentIndex)
        );

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), aliceBalance_ + bobBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_wholeBalance(uint256 index_, uint256 principal_) external {
        _mToken.setLatestIndex(bound(index_, 1_111111111111, 10_000000000000));

        principal_ = bound(principal_, 999999, 1_000_000_000_000000);

        _mToken.setPrincipalOfTotalEarningSupply(principal_);
        _mToken.setPrincipalOfTotalEarningSupply(principal_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, principal_);

        uint256 balance_ = _mToken.balanceOf(_alice);

        vm.prank(_alice);
        _mToken.transfer(_bob, balance_);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_mToken.balanceOf(_bob), balance_);
    }

    /* ============ startEarning ============ */
    function test_startEarning_notApprovedEarner() external {
        vm.expectRevert(IMToken.NotApprovedEarner.selector);
        vm.prank(_alice);
        _mToken.startEarning();
    }

    function test_startEarning() external {
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _registrar.addToList(RegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);

        vm.expectEmit();
        emit IMToken.StartedEarning(_alice);

        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 909);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_startEarning(uint256 supply_) external {
        supply_ = bound(supply_, 1, type(uint112).max);

        _mToken.setTotalNonEarningSupply(supply_);

        _mToken.setInternalBalanceOf(_alice, supply_);

        _registrar.addToList(RegistrarReader.EARNERS_LIST, _alice);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(supply_), _expectedCurrentIndex);

        vm.prank(_alice);
        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_startEarning_overflow() external {
        _mToken.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE);

        uint256 aliceBalance_ = uint256(type(uint112).max) + 20;

        _mToken.setTotalNonEarningSupply(aliceBalance_);
        _mToken.setInternalBalanceOf(_alice, aliceBalance_);

        _registrar.addToList(RegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _mToken.startEarning();
    }

    /* ============ stopEarning ============ */
    function test_stopEarning() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_alice);

        vm.expectEmit();
        emit IMToken.StoppedEarning(_alice);

        _mToken.stopEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_stopEarning(uint256 supply_) external {
        supply_ = bound(supply_, 1, type(uint112).max / 10);

        _mToken.setPrincipalOfTotalEarningSupply(supply_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, supply_);

        // Since Alice has stopped earning, the principal balance should reflect the interest accumulated until now.
        // To calculate this amount, we compute the present amount.
        uint256 expectedPrincipalBalance_ = _getPresentAmountRoundedDown(uint112(supply_), _expectedCurrentIndex);

        vm.prank(_alice);
        _mToken.stopEarning();

        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);

        assertEq(_mToken.totalNonEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_stopEarningForAccount_isApprovedEarner() external {
        _registrar.addToList(RegistrarReader.EARNERS_LIST, _alice);

        vm.expectRevert(IMToken.IsApprovedEarner.selector);
        _mToken.stopEarning(_alice);
    }

    function test_stopEarningForAccount() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.expectEmit();
        emit IMToken.StoppedEarning(_alice);

        _mToken.stopEarning(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_stopEarningForAccount(uint256 supply_) external {
        supply_ = bound(supply_, 1, type(uint112).max / 10);

        _mToken.setPrincipalOfTotalEarningSupply(supply_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, supply_);

        // Since Alice has stopped earning, the principal balance should reflect the interest accumulated until now.
        // To calculate this amount, we compute the present amount.
        uint256 expectedPrincipalBalance_ = _getPresentAmountRoundedDown(uint112(supply_), _expectedCurrentIndex);

        _mToken.stopEarning(_alice);

        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);

        assertEq(_mToken.totalNonEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    /* ============ updateIndex ============ */
    function test_updateIndex_notPortal() external {
        vm.expectRevert(IMToken.NotPortal.selector);
        _mToken.updateIndex(0);
    }

    function test_updateIndex() external {
        uint256 expectedLatestUpdateTimestamp_ = _start;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        vm.prank(_portal);
        _mToken.updateIndex(_expectedCurrentIndex *= 2);

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_000); // Is not dependent on latestIndex.
    }

    function test_balanceOf_earner() external {
        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        assertEq(_mToken.balanceOf(_alice), 999);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_090); // Is dependent on latestIndex.
    }

    /* ============ totalNonEarningSupply ============ */
    function test_totalEarningSupply() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalEarningSupply(), 999);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalEarningSupply(), 1_090); // Is dependent on latestIndex.
    }

    function test_totalNonEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000); // Is not dependent on latestIndex.
    }

    /* ============ totalSupply ============ */
    function test_totalSupply_noTotalEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalSupply(), 1_000);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestIndex.
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalSupply(), 999);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_090); // Is dependent on latestIndex.
    }

    function test_totalSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalSupply(), 1_999);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalSupply(), 1_999);

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 2_090); // Is dependent on latestIndex.
    }
}
