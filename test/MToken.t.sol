// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { stdError } from "../lib/forge-std/src/Test.sol";

import { IERC20Extended } from "../lib/common/src/interfaces/IERC20Extended.sol";
import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";
import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

import { MockMinterGateway, MockRateModel, MockTTGRegistrar } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";
import { TestUtils } from "./utils/TestUtils.sol";

contract MTokenTests is TestUtils {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");
    address internal _minterGateway = makeAddr("minterGateway");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint32 internal _earnerRate = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY
    uint256 internal _start = vm.getBlockTimestamp();

    uint128 internal _expectedCurrentIndex;

    MockRateModel internal _earnerRateModel;
    MockTTGRegistrar internal _registrar;
    MTokenHarness internal _mToken;

    function setUp() external {
        _earnerRateModel = new MockRateModel();

        _earnerRateModel.setRate(_earnerRate);

        _registrar = new MockTTGRegistrar();

        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, address(_earnerRateModel));

        _mToken = new MTokenHarness(address(_registrar), _minterGateway);

        _mToken.setLatestRate(_earnerRate);

        vm.warp(_start + 30_057_038); // Just enough time for the index to be ~1.1.

        _expectedCurrentIndex = 1_100000068703;
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_mToken.ttgRegistrar(), address(_registrar));
        assertEq(_mToken.minterGateway(), _minterGateway);
    }

    function test_constructor_zeroTTGRegistrar() external {
        vm.expectRevert(IMToken.ZeroTTGRegistrar.selector);
        new MTokenHarness(address(0), _minterGateway);
    }

    function test_constructor_zeroMinterGateway() external {
        vm.expectRevert(IMToken.ZeroMinterGateway.selector);
        new MTokenHarness(address(_registrar), address(0));
    }

    /* ============ mint ============ */
    function test_mint_notMinterGateway() external {
        vm.expectRevert(IMToken.NotMinterGateway.selector);
        _mToken.mint(_alice, 0);
    }

    function test_mint_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 0);
    }

    function test_mint_invalidRecipient() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(_minterGateway);
        _mToken.mint(address(0), 1_000);
    }

    function test_mint_toNonEarner() external {
        vm.prank(_minterGateway);
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.internalBalanceOf(_alice), 1_000);
        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_mint_toNonEarner(uint256 amount_) external {
        amount_ = bound(amount_, 1, type(uint112).max);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, amount_);

        assertEq(_mToken.internalBalanceOf(_alice), amount_);
        assertEq(_mToken.totalNonEarningSupply(), amount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_mint_toNonEarner_overflowPrincipalOfTotalSupply() external {
        // Set rate to 0 to keep index at 1.
        _mToken.setLatestRate(0);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, type(uint112).max - 1);

        vm.prank(_minterGateway);
        vm.expectRevert(IMToken.OverflowsPrincipalOfTotalSupply.selector);
        _mToken.mint(_bob, 2);
    }

    function test_mint_toEarner() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 999);

        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 1);

        // No change due to principal round down on mint.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 2);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 909);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_mint_toEarner(uint256 amount_) external {
        amount_ = bound(amount_, 1, type(uint112).max);

        _mToken.setLatestRate(_earnerRate);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, amount_);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(amount_), _mToken.currentIndex());

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 1);

        expectedPrincipalBalance_ += _getPrincipalAmountRoundedDown(uint240(1), _mToken.currentIndex());

        // No change due to principal round down on mint.
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 2);

        expectedPrincipalBalance_ += _getPrincipalAmountRoundedDown(uint240(2), _mToken.currentIndex());

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function test_mint_toEarner_overflowPrincipalOfTotalSupply() external {
        // Set rate to 0 to keep index at 1.
        _mToken.setLatestRate(0);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_minterGateway);

        vm.expectRevert(IMToken.OverflowsPrincipalOfTotalSupply.selector);
        _mToken.mint(_alice, type(uint112).max);
    }

    /* ============ burn ============ */
    function test_burn_notMinterGateway() external {
        vm.expectRevert(IMToken.NotMinterGateway.selector);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientBalance_fromNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 999, 1_000));
        vm.prank(_minterGateway);
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_insufficientBalance_fromEarner() external {
        _mToken.setLatestRate(_earnerRate);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(abi.encodeWithSelector(IMToken.InsufficientBalance.selector, _alice, 908, 910));
        vm.prank(_minterGateway);
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_fromNonEarner() external {
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 500);
        assertEq(_mToken.totalNonEarningSupply(), 500);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_burn_fromNonEarner(uint256 supply_) external {
        supply_ = bound(supply_, 2, type(uint112).max);
        vm.assume(supply_ % 2 == 0);

        _mToken.setTotalNonEarningSupply(supply_);
        _mToken.setInternalBalanceOf(_alice, supply_);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, supply_ / 2);

        assertEq(_mToken.internalBalanceOf(_alice), supply_ / 2);
        assertEq(_mToken.totalNonEarningSupply(), supply_ / 2);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, supply_ / 2);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_burn_fromEarner() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 998);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_burn_fromEarner(uint256 amount_) external {
        amount_ = bound(amount_, 2, type(uint112).max);
        vm.assume(amount_ % 2 == 0);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(amount_), _mToken.currentIndex());

        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(expectedPrincipalBalance_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, expectedPrincipalBalance_);

        uint256 burnAmount_ = _mToken.balanceOf(_alice) / 2;
        vm.assume(burnAmount_ != 0);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, burnAmount_);

        expectedPrincipalBalance_ -= _getPrincipalAmountRoundedUp(uint240(burnAmount_), _mToken.currentIndex());

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        uint256 balanceOfAlice_ = _mToken.balanceOf(_alice);

        assertEq(
            _mToken.balanceOf(_alice),
            _getPresentAmountRoundedDown(uint112(expectedPrincipalBalance_), _mToken.currentIndex())
        );

        vm.prank(_minterGateway);
        _mToken.burn(_alice, balanceOfAlice_);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
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

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_alice);
        _mToken.transfer(_bob, 1_000);
    }

    function test_transfer_insufficientBalance_fromEarner_toNonEarner() external {
        _mToken.setLatestRate(_earnerRate);

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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _mToken.setLatestRate(_earnerRate);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.prank(_alice);
        _mToken.transfer(_bob, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 453);

        assertEq(_mToken.internalBalanceOf(_bob), 1_001);

        assertEq(_mToken.totalNonEarningSupply(), 1_001);
        assertEq(_mToken.principalOfTotalEarningSupply(), 453);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_transfer_fromEarner_toNonEarner(
        uint256 amountEarning_,
        uint256 nonEarningSupply_,
        uint256 transferAmount_
    ) external {
        amountEarning_ = bound(amountEarning_, 2, type(uint112).max);
        transferAmount_ = bound(transferAmount_, 1, amountEarning_);
        nonEarningSupply_ = bound(nonEarningSupply_, 1, type(uint112).max);

        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(amountEarning_);
        _mToken.setTotalNonEarningSupply(nonEarningSupply_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, amountEarning_);

        _mToken.setInternalBalanceOf(_bob, nonEarningSupply_);

        uint256 expectedPrincipalBalance_ = amountEarning_ -
            _getPrincipalAmountRoundedUp(uint240(transferAmount_), _mToken.currentIndex());

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.internalBalanceOf(_bob), nonEarningSupply_ + transferAmount_);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ + transferAmount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());

        vm.assume(_mToken.balanceOf(_alice) != 0);

        vm.prank(_alice);
        _mToken.transfer(_bob, 1);

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_ - 1);
        assertEq(_mToken.internalBalanceOf(_bob), nonEarningSupply_ + transferAmount_ + 1);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ + transferAmount_ + 1);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_ - 1);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function test_transfer_fromEarner_toNonEarner_noOverflow() external {
        // Earner balances being capped to type(uint112).max
        // and non earners ones to type(uint240).max,
        // it is not possible to overflow the non earning balances
        // since the earning balances will always be lower.
        uint256 aliceBalance_ = type(uint112).max;
        uint256 bobBalance_ = 2;

        // Set rate to 0 to keep index at 1.
        _mToken.setLatestRate(0);

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
        _mToken.setLatestRate(_earnerRate);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_transfer_fromNonEarner_toEarner(
        uint256 earningSupply_,
        uint256 nonEarningSupply_,
        uint256 transferAmount_
    ) external {
        earningSupply_ = bound(earningSupply_, 1, type(uint112).max / 2);
        nonEarningSupply_ = bound(nonEarningSupply_, 1, type(uint112).max / 2);
        transferAmount_ = bound(transferAmount_, 1, nonEarningSupply_);

        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(earningSupply_);
        _mToken.setTotalNonEarningSupply(nonEarningSupply_);

        _mToken.setInternalBalanceOf(_alice, nonEarningSupply_);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, earningSupply_);

        uint256 expectedPrincipalBalance_ = earningSupply_ +
            _getPrincipalAmountRoundedDown(uint240(transferAmount_), _mToken.currentIndex());

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(_mToken.internalBalanceOf(_alice), nonEarningSupply_ - transferAmount_);

        assertEq(_mToken.internalBalanceOf(_bob), expectedPrincipalBalance_);

        assertEq(_mToken.totalNonEarningSupply(), nonEarningSupply_ - transferAmount_);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setPrincipalOfTotalEarningSupply(1_364);
        _mToken.setLatestRate(_earnerRate);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
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
        _mToken.setLatestRate(_earnerRate);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, aliceBalance_);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, bobBalance_);

        uint128 currentIndex_ = _mToken.currentIndex();

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        assertEq(
            _mToken.internalBalanceOf(_alice),
            aliceBalance_ - _getPrincipalAmountRoundedUp(uint240(transferAmount_), currentIndex_)
        );

        assertEq(
            _mToken.internalBalanceOf(_bob),
            bobBalance_ + _getPrincipalAmountRoundedUp(uint240(transferAmount_), currentIndex_)
        );

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), aliceBalance_ + bobBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function testFuzz_transfer_wholeBalance(uint256 index_, uint256 rate_, uint256 principal_) external {
        _mToken.setLatestIndex(bound(index_, 1_111111111111, 10_000000000000));
        _mToken.setLatestRate(bound(rate_, 10, 10_000));

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
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);

        vm.expectEmit();
        emit IMToken.StartedEarning(_alice);

        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), 909);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_startEarning(uint256 supply_) external {
        supply_ = bound(supply_, 1, type(uint112).max);

        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalNonEarningSupply(supply_);

        _mToken.setInternalBalanceOf(_alice, supply_);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        uint256 expectedPrincipalBalance_ = _getPrincipalAmountRoundedDown(uint240(supply_), _mToken.currentIndex());

        vm.prank(_alice);
        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.principalOfTotalEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function test_startEarning_overflow() external {
        uint256 aliceBalance_ = uint256(type(uint112).max) + 20;

        // Set rate to 0 to keep index at 1.
        _mToken.setLatestRate(0);

        _mToken.setTotalNonEarningSupply(aliceBalance_);
        _mToken.setInternalBalanceOf(_alice, aliceBalance_);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        vm.prank(_alice);

        vm.expectRevert(UIntMath.InvalidUInt112.selector);
        _mToken.startEarning();
    }

    /* ============ stopEarning ============ */
    function test_stopEarning() external {
        _mToken.setLatestRate(_earnerRate);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    function testFuzz_stopEarning(uint256 supply_) external {
        supply_ = bound(supply_, 1, type(uint112).max / 10);

        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(supply_);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, supply_);

        // Since Alice has stopped earning, the principal balance should reflect the interest accumulated until now.
        // To calculate this amount, we compute the present amount.
        uint256 expectedPrincipalBalance_ = _getPresentAmountRoundedDown(uint112(supply_), _mToken.currentIndex());

        vm.prank(_alice);
        _mToken.stopEarning();

        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.internalBalanceOf(_alice), expectedPrincipalBalance_);

        assertEq(_mToken.totalNonEarningSupply(), expectedPrincipalBalance_);
        assertEq(_mToken.principalOfTotalEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), vm.getBlockTimestamp());
    }

    /* ============ updateIndex ============ */
    function test_updateIndex() external {
        _mToken.setLatestRate(_earnerRate);

        uint256 expectedLatestIndex_ = ContinuousIndexingMath.EXP_SCALED_ONE;
        uint256 expectedLatestUpdateTimestamp_ = _start;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        _expectedCurrentIndex = uint128(
            ContinuousIndexingMath.multiplyIndicesDown(
                ContinuousIndexingMath.EXP_SCALED_ONE,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(_earnerRate),
                    uint32(vm.getBlockTimestamp() - _start)
                )
            )
        );

        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = vm.getBlockTimestamp();

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _earnerRateModel.setRate(_earnerRate / 2);

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate); // Has not changed yet.
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        _expectedCurrentIndex = uint128(
            ContinuousIndexingMath.multiplyIndicesDown(
                _expectedCurrentIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(_earnerRate / 2),
                    365 days
                )
            )
        );

        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = vm.getBlockTimestamp();

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.balanceOf(_alice), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_000); // Is not dependent on latestIndex.
    }

    function test_balanceOf_earner() external {
        _mToken.setLatestRate(_earnerRate);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        assertEq(_mToken.balanceOf(_alice), 999);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.balanceOf(_alice), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_202); // Is dependent on latestIndex.
    }

    /* ============ totalNonEarningSupply ============ */
    function test_totalEarningSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalEarningSupply(), 999);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalEarningSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalEarningSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalEarningSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalNonEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalNonEarningSupply(), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000); // Is not dependent on latestIndex.
    }

    /* ============ totalSupply ============ */
    function test_totalSupply_noTotalEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalSupply(), 1_000);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalSupply(), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestIndex.
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalSupply(), 999);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalNonEarningSupply(1_000);
        _mToken.setPrincipalOfTotalEarningSupply(909);

        assertEq(_mToken.totalSupply(), 1_999);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(_mToken.totalSupply(), 2_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 2_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 2_202); // Is dependent on latestIndex.
    }

    /* ============ earnerRate ============ */
    function test_earnerRate() external {
        assertEq(_mToken.earnerRate(), _earnerRate);

        _earnerRateModel.setRate(_earnerRate / 2);

        assertEq(_mToken.earnerRate(), _earnerRate);

        _mToken.updateIndex();

        assertEq(_mToken.earnerRate(), _earnerRate / 2);
    }

    function test_latestEarnerRate() external {
        assertEq(_mToken.earnerRate(), _earnerRate);

        _mToken.setLatestRate(_earnerRate / 2);

        assertEq(_mToken.earnerRate(), _earnerRate / 2);
    }

    /* ============ emptyRateModel ============ */
    function test_emptyRateModel() external {
        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, address(0));

        assertEq(_mToken.rate(), 0);
    }
}
