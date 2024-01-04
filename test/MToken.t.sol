// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { stdError, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";
import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

import { MockMinterGateway, MockRateModel, MockTTGRegistrar } from "./utils/Mocks.sol";
import { MTokenHarness } from "./utils/MTokenHarness.sol";

// TODO: Fuzz and/or invariant tests.

contract MTokenTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");
    address internal _minterGateway = makeAddr("minterGateway");

    address[] internal _accounts = [_alice, _bob, _charlie, _david];

    uint32 internal _earnerRate = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY
    uint256 internal _start = block.timestamp;

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
        _mToken = new MTokenHarness(address(0), _minterGateway);
    }

    function test_constructor_zeroMinterGateway() external {
        vm.expectRevert(IMToken.ZeroMinterGateway.selector);
        _mToken = new MTokenHarness(address(_registrar), address(0));
    }

    /* ============ mint ============ */
    function test_mint_notMinterGateway() external {
        vm.expectRevert(IMToken.NotMinterGateway.selector);
        _mToken.mint(_alice, 0);
    }

    function test_mint_toNonEarner() external {
        vm.prank(_minterGateway);
        _mToken.mint(_alice, 1_000);

        assertEq(_mToken.internalBalanceOf(_alice), 1_000);
        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_mint_toEarner() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setIsEarning(_alice, true);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 999);

        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 1);

        // No change due to principal round down on mint.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);

        vm.prank(_minterGateway);
        _mToken.mint(_alice, 2);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    /* ============ burn ============ */
    function test_burn_notMinterGateway() external {
        vm.expectRevert(IMToken.NotMinterGateway.selector);
        _mToken.burn(_alice, 0);
    }

    function test_burn_insufficientBalance_fromNonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 999);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(_minterGateway);
        _mToken.burn(_alice, 1_000);
    }

    function test_burn_insufficientBalance_fromEarner() external {
        _mToken.setLatestRate(_earnerRate);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 908);

        vm.expectRevert(stdError.arithmeticError);
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
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestUpdateTimestamp(), _start);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_burn_fromEarner() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 908);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 908);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);

        vm.prank(_minterGateway);
        _mToken.burn(_alice, 998);

        assertEq(_mToken.internalBalanceOf(_alice), 0);
        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    /* ============ transfer ============ */
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    function test_transfer_fromEarner_toNonEarner() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);
        _mToken.setTotalNonEarningSupply(500);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setInternalBalanceOf(_bob, 500);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 454);

        assertEq(_mToken.internalBalanceOf(_bob), 1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 454);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);

        vm.prank(_alice);
        _mToken.transfer(_bob, 1);

        // Change due to principal round up on burn.
        assertEq(_mToken.internalBalanceOf(_alice), 453);

        assertEq(_mToken.internalBalanceOf(_bob), 1_001);

        assertEq(_mToken.totalNonEarningSupply(), 1_001);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 453);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_transfer_fromNonEarner_toEarner() external {
        _mToken.setLatestRate(_earnerRate);
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
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_transfer_fromEarner_toEarner() external {
        _mToken.setTotalPrincipalOfEarningSupply(1_364);
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(1_364);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.setIsEarning(_bob, true);
        _mToken.setInternalBalanceOf(_bob, 454);

        vm.prank(_alice);
        _mToken.transfer(_bob, 500);

        assertEq(_mToken.internalBalanceOf(_alice), 454);

        assertEq(_mToken.internalBalanceOf(_bob), 909);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 1_364);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_mToken.latestUpdateTimestamp(), _start);
    }

    /* ============ startEarning ============ */
    function test_startEarning_onBehalfOf_notApprovedEarner() external {
        vm.prank(_alice);
        _mToken.allowEarningOnBehalf();

        vm.expectRevert(IMToken.NotApprovedEarner.selector);
        _mToken.startEarningOnBehalfOf(_alice);
    }

    function test_startEarning_onBehalfOf_hasNotAllowedEarningOnBehalf() external {
        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        vm.expectRevert(IMToken.HasNotAllowedEarningOnBehalf.selector);
        _mToken.startEarningOnBehalfOf(_alice);
    }

    function test_startEarning_onBehalfOf() external {
        vm.prank(_alice);
        _mToken.allowEarningOnBehalf();

        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalNonEarningSupply(1_000);

        _mToken.setInternalBalanceOf(_alice, 1_000);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        _mToken.startEarningOnBehalfOf(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

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
        _mToken.startEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 909);
        assertEq(_mToken.isEarning(_alice), true);

        assertEq(_mToken.totalNonEarningSupply(), 0);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 909);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    /* ============ stopEarning ============ */
    function test_stopEarning_onBehalfOf_isApprovedEarner() external {
        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _alice);

        vm.expectRevert(IMToken.IsApprovedEarner.selector);
        _mToken.stopEarningOnBehalfOf(_alice);
    }

    function test_stopEarning_onBehalfOf() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        _mToken.stopEarningOnBehalfOf(_alice);

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
    }

    function test_stopEarning() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        _mToken.setIsEarning(_alice, true);
        _mToken.setInternalBalanceOf(_alice, 909);

        vm.prank(_alice);
        _mToken.stopEarning();

        assertEq(_mToken.internalBalanceOf(_alice), 999);
        assertEq(_mToken.isEarning(_alice), false);
        assertEq(_mToken.hasAllowedEarningOnBehalf(_alice), false);

        assertEq(_mToken.totalNonEarningSupply(), 999);
        assertEq(_mToken.totalPrincipalOfEarningSupply(), 0);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), _expectedCurrentIndex);
        assertEq(_mToken.latestUpdateTimestamp(), block.timestamp);
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

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = ContinuousIndexingMath.multiplyDown(
            ContinuousIndexingMath.EXP_SCALED_ONE,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_earnerRate),
                uint32(block.timestamp - _start)
            )
        );

        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = block.timestamp;

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

        vm.warp(block.timestamp + 365 days);

        _expectedCurrentIndex = ContinuousIndexingMath.multiplyDown(
            _expectedCurrentIndex,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_earnerRate / 2),
                365 days
            )
        );

        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);

        _mToken.updateIndex();

        expectedLatestIndex_ = _expectedCurrentIndex;
        expectedLatestUpdateTimestamp_ = block.timestamp;

        assertEq(_mToken.currentIndex(), _expectedCurrentIndex);
        assertEq(_mToken.earnerRate(), _earnerRate / 2);
        assertEq(_mToken.latestIndex(), expectedLatestIndex_);
        assertEq(_mToken.latestUpdateTimestamp(), expectedLatestUpdateTimestamp_);
    }

    /* ============ balanceOf ============ */
    function test_balanceOf_nonEarner() external {
        _mToken.setInternalBalanceOf(_alice, 1_000);

        assertEq(_mToken.balanceOf(_alice), 1_000);

        vm.warp(block.timestamp + 365 days);

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

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.balanceOf(_alice), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.balanceOf(_alice), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.balanceOf(_alice), 1_202); // Is dependent on latestIndex.
    }

    /* ============ totalNonEarningSupply ============ */
    function test_totalEarningSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalEarningSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalEarningSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalEarningSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalEarningSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalNonEarningSupply() external {
        _mToken.setTotalNonEarningSupply(1_000);

        assertEq(_mToken.totalNonEarningSupply(), 1_000);

        vm.warp(block.timestamp + 365 days);

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

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_000);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_000); // Is not dependent on latestIndex.
    }

    function test_totalSupply_onlyTotalEarningSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalSupply(), 999);

        vm.warp(block.timestamp + 365 days);

        assertEq(_mToken.totalSupply(), 1_105);

        _mToken.setLatestRate(_earnerRate / 2); // 5% APY

        assertEq(_mToken.totalSupply(), 1_002); // Is dependent on latestRate.

        _mToken.setLatestIndex(1_200_000_000_000);

        assertEq(_mToken.totalSupply(), 1_202); // Is dependent on latestIndex.
    }

    function test_totalSupply() external {
        _mToken.setLatestRate(_earnerRate);
        _mToken.setTotalNonEarningSupply(1_000);
        _mToken.setTotalPrincipalOfEarningSupply(909);

        assertEq(_mToken.totalSupply(), 1_999);

        vm.warp(block.timestamp + 365 days);

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

    /* ============ allowEarningOnBehalf ============ */
    function test_allowEarningOnBehalf() external {
        // Earning on behalf is disabled by default
        assertFalse(_mToken.hasAllowedEarningOnBehalf(_alice));

        vm.expectEmit();
        emit IMToken.AllowedEarningOnBehalf(_alice);

        vm.prank(_alice);
        _mToken.allowEarningOnBehalf();

        assertTrue(_mToken.hasAllowedEarningOnBehalf(_alice));
    }

    /* ============ disallowEarningOnBehalf ============ */
    function test_disallowEarningOnBehalf() external {
        _mToken.allowEarningOnBehalf();

        vm.expectEmit();
        emit IMToken.DisallowedEarningOnBehalf(_alice);

        vm.prank(_alice);
        _mToken.disallowEarningOnBehalf();

        assertFalse(_mToken.hasAllowedEarningOnBehalf(_alice));
    }

    /* ============ emptyRateModel ============ */
    function test_emptyRateModel() external {
        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, address(0));

        assertEq(_mToken.rate(), 0);
    }
}
