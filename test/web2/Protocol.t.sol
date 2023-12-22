// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test, Vm } from "../../lib/forge-std/src/Test.sol";
import { ProtocolHarness } from "./util/ProtocolHarness.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";
import { IRateModel } from "../../src/interfaces/IRateModel.sol";
import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

contract ProtocolTest is Test {
    ProtocolHarness _protocol;

    address internal _protocolAddress;
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _mTokenAddress = makeAddr("mToken");
    address internal _vaultAddress = makeAddr("vault");
    address internal _minterRateModelAddress = makeAddr("minterRateModel");

    address internal _aliceAddress = makeAddr("alice");
    address internal _bobAddress = makeAddr("bob");
    address internal _charlieAddress = makeAddr("charlie");
    address internal _davidAddress = makeAddr("david");

    function setUp() public {
        // vault
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.vault.selector),
            abi.encode(_vaultAddress)
        );

        _protocol = new ProtocolHarness(_spogRegistrarAddress, _mTokenAddress);
        _protocolAddress = address(_protocol);
    }

    function test_setUp() public {
        assertEq(_spogRegistrarAddress, _protocol.spogRegistrar(), "Setup spogRegistrar address failed");
        assertEq(_vaultAddress, _protocol.spogVault(), "Setup vault failed");
        assertEq(_mTokenAddress, _protocol.mToken(), "Setup mToken address failed");
    }

    /******************************************************************************************************************\
    |                                          External Interactive Functions                                          |
    \******************************************************************************************************************/

    function test_activateMinter_RevertNotApprovedMinter() public {
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);

        _protocol.activateMinter(_aliceAddress);
    }

    function test_activateMinter_RevertAlreadyActiveMinter() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, true);

        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.AlreadyActiveMinter.selector);

        _protocol.activateMinter(_aliceAddress);
    }

    function test_activateMinter_NewMinter() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        vm.prank(_bobAddress);
        vm.expectEmit(true, true, false, true, address(_protocolAddress));
        emit IProtocol.MinterActivated(_aliceAddress, _bobAddress);

        _protocol.activateMinter(_aliceAddress);
        assertTrue(_protocol.isActiveMinter(_aliceAddress));
    }

    function test_activateMinter_ReactivateMinter() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, false);

        vm.prank(_bobAddress);
        vm.expectEmit(true, true, false, true, address(_protocolAddress));
        emit IProtocol.MinterActivated(_aliceAddress, _bobAddress);

        _protocol.activateMinter(_aliceAddress);
        assertTrue(_protocol.isActiveMinter(_aliceAddress));
    }

    function test_burnM() public {
        //uint256 activeOwedM_ = _setDefaultsWithoutPenalty();

        // TODO test _imposePenaltyIfMissedCollateralUpdates first
    }

    function test_cancelMint_invalid_mint_id() public {
        _allowList(SPOGRegistrarReader.VALIDATORS_LIST, _bobAddress);
        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        _protocol.cancelMint(_aliceAddress, 123);
    }

    function test_cancelMint_not_approved_validator() public {
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, 777666555, _aliceAddress);
        _denyList(SPOGRegistrarReader.VALIDATORS_LIST, _bobAddress);
        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.cancelMint(_aliceAddress, mintId);
    }

    function test_cancelMint() public {
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, 777666555, _aliceAddress);
        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp_) = _protocol.external_mintProposal(
            _aliceAddress
        );

        assertEq(mintId_, mintId);
        assertEq(destination_, _aliceAddress);
        assertEq(amount_, 1234);
        assertEq(timestamp_, 777666555);

        // set Bob approved validator
        _allowList(SPOGRegistrarReader.VALIDATORS_LIST, _bobAddress);

        vm.expectEmit(true, true, false, false);
        emit IProtocol.MintCanceled(mintId, _bobAddress);
        vm.prank(_bobAddress);
        _protocol.cancelMint(_aliceAddress, mintId);
    }

    function test_deactivateMinter_RevertStillApprovedMinter() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.StillApprovedMinter.selector);

        _protocol.deactivateMinter(_aliceAddress);
    }

    function test_deactivateMinter_RevertInactiveMinter() public {
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, false);

        vm.prank(_bobAddress);
        vm.expectRevert(IProtocol.InactiveMinter.selector);

        _protocol.deactivateMinter(_aliceAddress);
    }

    /**
     * TODO Here are a lot of invariants for totals
     */
    function test_deactivateMinter_fixedIndex() public {
        uint256 activeOwedM_ = _setDefaultsWithoutPenalty();

        // Minter Rate
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        _minterRateModelRate(20);

        // MToken
        _mTokenTotalSupply(1000e18); // 10 times the amount of minter
        _mTokenNextIndex(1); // TODO put sane value here

        // ActiveOwedM, no penalty
        uint256 _inactiveOwedM = activeOwedM_;

        _protocol.setter_totalPrincipalOfActiveOwedM((100e18) + 444);
        _protocol.setter_totalInactiveOwedM(333);

        // Minter settings
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_inactiveOwedM(_aliceAddress, 222);
        _protocol.setter_collateral(_aliceAddress, 100e18); // PoR
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // collateral
        // TODO _protocol.setter_mintProposals(_aliceAddress, 1000);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, 10 days);

        // VM settings: execute as box on day 14
        vm.prank(_bobAddress);

        // Expect event
        vm.expectEmit(true, true, false, true, address(_protocolAddress));
        emit IProtocol.MinterDeactivated(_aliceAddress, _inactiveOwedM, _bobAddress);

        // Actual function call
        _protocol.deactivateMinter(_aliceAddress);

        // Check result
        assertEq(222 + _inactiveOwedM, _protocol.inactiveOwedMOf(_aliceAddress));
        assertEq(333 + _inactiveOwedM, _protocol.totalInactiveOwedM());
        assertEq(444, _protocol.getter_totalPrincipalOfActiveOwedM());

        assertFalse(_protocol.isActiveMinter(_aliceAddress));
        assertEq(0, _protocol.collateralOf(_aliceAddress));
        assertEq(0, _protocol.lastUpdateIntervalOf(_aliceAddress));
        assertEq(0, _protocol.lastUpdateOf(_aliceAddress));
        // TODO asseert for mint proposal
        assertEq(0, _protocol.penalizedUntilOf(_aliceAddress));
        assertEq(0, _protocol.getter_principalOfActiveOwedM(_aliceAddress));
        assertEq(0, _protocol.unfrozenTimeOf(_aliceAddress));

        // TODO check is index is updated
    }

    function test_freezeMinter() public {}

    function test_mintM_not_active_minter() public {
        vm.prank(_aliceAddress);
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        _protocol.mintM(123);
    }

    function test_mintM_frozen_minter() public {
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp + 1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        vm.prank(_aliceAddress);
        _protocol.mintM(123);
    }

    function test_mintM_invalid_mint_id() public {
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_aliceAddress);
        _protocol.mintM(123);
    }

    function test_mintM_pending() public {
        _setValue(SPOGRegistrarReader.MINT_DELAY, 12345);
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, block.timestamp - _protocol.mintDelay() + 1, _aliceAddress);
        _protocol.external_mintProposal(_aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IProtocol.PendingMintProposal.selector, block.timestamp + 1));
        vm.prank(_aliceAddress);
        _protocol.mintM(mintId);
    }

    function test_mintM_expired() public {
        _setValue(SPOGRegistrarReader.MINT_DELAY, 12345);
        _setValue(SPOGRegistrarReader.MINT_TTL, 12345);
        _setValue(SPOGRegistrarReader.MINT_RATIO, 12);
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, block.timestamp - _protocol.mintDelay() - _protocol.mintDelay() - 1, _aliceAddress);
        _protocol.external_mintProposal(_aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IProtocol.ExpiredMintProposal.selector, block.timestamp - 1));
        vm.prank(_aliceAddress);
        _protocol.mintM(mintId);

    }

    function test_mintM_undercollateralized() public {
        _setValue(SPOGRegistrarReader.MINT_DELAY, 12345);
        _setValue(SPOGRegistrarReader.MINT_TTL, 12345);
        _setValue(SPOGRegistrarReader.MINT_RATIO, 12);
        _protocol.setter_collateral(_aliceAddress, 123);
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, block.timestamp - _protocol.mintDelay() - _protocol.mintDelay(), _aliceAddress);
        _protocol.external_mintProposal(_aliceAddress);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 1234, 0));
        vm.prank(_aliceAddress);
        _protocol.mintM(mintId);
    }

    function test_mintM_positive() public {
        _protocol.setter_latestRate(100);
        _setValue(SPOGRegistrarReader.MINT_DELAY, 12345);
        _setValue(SPOGRegistrarReader.MINT_TTL, 12345);
        _setValue(SPOGRegistrarReader.MINT_RATIO, 1);
        _protocol.setter_collateral(_aliceAddress, 1e10);
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);
        // create a mint proposal
        uint256 mintId = _protocol.setter_mintProposals(_aliceAddress, 1234, block.timestamp - _protocol.mintDelay() - _protocol.mintDelay(), _aliceAddress);
        _protocol.external_mintProposal(_aliceAddress);

        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IMToken.mint.selector, _aliceAddress, 1234),
            abi.encode(true)
        );
        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IContinuousIndexing.currentIndex.selector),
            abi.encode(1e18)
        );
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IContinuousIndexing.updateIndex.selector),
            abi.encode(1e18)
        );
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        _minterRateModelRate(20);
        _mTokenTotalSupply(1234);
        vm.expectEmit(true, false, false, false);
        emit IProtocol.MintExecuted(mintId);
        vm.expectEmit(true, true, false, false);
        emit IContinuousIndexing.IndexUpdated(1e18, 20);
        vm.prank(_aliceAddress);
        _protocol.mintM(mintId);
    }

    function test_proposeMint_not_active_minter() public {
        vm.prank(_aliceAddress);
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        _protocol.proposeMint(123, _aliceAddress);
    }

    function test_proposeMint_frozen_minter() public {
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp + 1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        vm.prank(_aliceAddress);
        _protocol.proposeMint(123, _aliceAddress);
    }

    function test_proposeMint_undercollateralized() public {
        _setValue(SPOGRegistrarReader.MINT_RATIO, 12);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_collateral(_aliceAddress, 123);
        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 123, 0));
        vm.prank(_aliceAddress);
        _protocol.proposeMint(123, _aliceAddress);
    }

    function test_proposeMint_positive() public {
        _setValue(SPOGRegistrarReader.MINT_RATIO, 10);
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_unfrozenTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_collateral(_aliceAddress, 1.23e5);
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);

        assertEq(_protocol.external_mintNonce(), 0);

        vm.prank(_aliceAddress);
        vm.expectEmit(false, true, true, true);
        emit IProtocol.MintProposed(123, _aliceAddress, 123, _aliceAddress);
        uint256 mintId = _protocol.proposeMint(123, _aliceAddress);

        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp_) = _protocol.external_mintProposal(_aliceAddress);
        assertEq(mintId_, mintId);
        assertEq(destination_, _aliceAddress);
        assertEq(amount_, 123);
        assertEq(timestamp_, block.timestamp);
        assertEq(_protocol.external_mintNonce(), 1);
    }

    function test_proposeRetrieval_not_active_minter() public {
        _protocol.setter_isActiveMinter(_aliceAddress, false);
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        vm.prank(_aliceAddress);
        _protocol.proposeRetrieval(1234);
    }

    function test_proposeRetrieval_undercollateralized() public {
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _setValue(SPOGRegistrarReader.MINT_RATIO, 1);
        _protocol.setter_collateral(_aliceAddress, 1);
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 2); // current amount 100
        vm.prank(_aliceAddress);
        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 2, 0));
        _protocol.proposeRetrieval(1234);
    }

    function test_proposeRetrieval_positive() public {
        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _setValue(SPOGRegistrarReader.MINT_RATIO, 1);
        _protocol.setter_collateral(_aliceAddress, 1e10);
        vm.prank(_aliceAddress);
        vm.expectEmit(false, true, true, false);
        emit IProtocol.RetrievalCreated(111, _aliceAddress, 1234);
        _protocol.proposeRetrieval(1234);
    }

    function test_updateCollateral() public {}

    function test_updateIndex() public {
        vm.mockCall(
            _protocolAddress,
            abi.encodeWithSelector(IContinuousIndexing.currentIndex.selector),
            abi.encode(1e18)
        );
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IContinuousIndexing.updateIndex.selector),
            abi.encode(1e18)
        );

        _protocol.setter_lastUpdateTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);

        _minterRateModelRate(20);
        _mTokenTotalSupply(1234);
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        _protocol.setter_totalPrincipalOfActiveOwedM(12345);
        _protocol.updateIndex();
    }

    /******************************************************************************************************************\
    |                                           External View/Pure Functions                                           |
    \******************************************************************************************************************/
    function test_activeOwedMOf_fixedIndex() public {
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount 100
        _protocol.override_fixedIndex(2e18); // hardcode index calculation

        assertEq(200e18, _protocol.activeOwedMOf(_aliceAddress));
    }

    function test_collateralOf_after_deadline() public {
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 0);
        _protocol.setter_lastUpdateInterval(_aliceAddress, 0);
        assertEq(_protocol.collateralOf(_aliceAddress), 0);
    }

    function test_collateralOf() public {
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);
        assertEq(_protocol.collateralOf(_aliceAddress), 0);
        _protocol.setter_collateral(_aliceAddress, 12345);
        assertEq(_protocol.collateralOf(_aliceAddress), 12345);
    }

    function test_collateralUpdateDeadlineOf() public {
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 60);
        _protocol.setter_lastUpdateInterval(_aliceAddress, 8);
        assertEq(_protocol.collateralUpdateDeadlineOf(_aliceAddress), 68);
        assertEq(_protocol.collateralUpdateDeadlineOf(_bobAddress), 0);
    }

    function test_excessActiveOwedM_none() public {
        _mTokenTotalSupply(1234);
        _protocol.setter_totalPrincipalOfActiveOwedM(123);
        uint256 result = _protocol.excessActiveOwedM();
        assertEq(result, 0);
    }

    function test_excessActiveOwedM() public {
       _mTokenTotalSupply(1234);
        _protocol.setter_totalPrincipalOfActiveOwedM(12345);
        uint256 result = _protocol.excessActiveOwedM();
        assertEq(result, 11111);
    }

    function test_getMaxAllowedOwedM_before_deadline() public {
        _setValue(SPOGRegistrarReader.MINT_RATIO, 10);
        _protocol.setter_collateral(_aliceAddress, 1.23e5);
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 0);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);
        assertEq(_protocol.getMaxAllowedOwedM(_aliceAddress), 0);
    }

    function test_getMaxAllowedOwedM() public {
        _setValue(SPOGRegistrarReader.MINT_RATIO, 10);
        _protocol.setter_collateral(_aliceAddress, 1.23e5);
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, block.timestamp);
        _protocol.setter_lastUpdateInterval(_aliceAddress, block.timestamp);
        assertEq(_protocol.getMaxAllowedOwedM(_aliceAddress), 123);

    }

    function test_getPenaltyForMissedCollateralUpdates_fixedIndex() public {
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 500); // 5%
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days);

        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount
        _protocol.override_fixedIndex(); // no compunding interest

        // Penalty Calculation (2 missed intervals)
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 12
        vm.warp(14 days);

        // 20 (rate in bps) * 2 (missed intervals) * (_currentM + _interestM) / 10_000 (conversion to basis point)
        assertEq(10e18, _protocol.getPenaltyForMissedCollateralUpdates(_aliceAddress));
    }

    /**
     * Test with a global update collateral interval of '0' (zero).
     */
    function test__getPenaltyBaseAndTimeForMissedCollateralUpdates_zeroUpdateCollateral() public {
        //uint256 activeOwedM = 100_038_363_521_300_872_800; // see test_activeOwedMOf_SevenDaysVanillaIndex
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100 * 1e18);
        _protocol.setter_latestIndex(1 * 1e18);
        _protocol.setter_latestUpdateTimestamp(7 days);
        _protocol.setter_latestRate(200);

        vm.warp(14 days);

        // Set a global '0' collateral update.
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 0);

        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 13
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 13

        // Fail with division by zero
        _protocol.external_getPenaltyBaseAndTimeForMissedCollateralUpdates(_aliceAddress);
    }

    function test_inactiveOwedMOf() public {}

    function test_isActiveMinter() public {}

    function test_isMinterApprovedByRegistrar_Allowed() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        assertTrue(_protocol.isMinterApprovedByRegistrar(_aliceAddress));
    }

    function test_isMinterApprovedByRegistrar_Denied() public {
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        assertFalse(_protocol.isMinterApprovedByRegistrar(_aliceAddress));
    }

    function test_isValidatorApprovedByRegistrar() public {}

    function test_lastUpdateIntervalOf() public {}

    function test_lastUpdateOf() public {}

    function test_mintDelay() public {}

    function test_minterFreezeTime() public {}

    function test_minterRate() public {}

    function test_mintProposalOf() public {}

    function test_mintRatio() public {}

    function test_mintTTL() public {}

    function test_penalizedUntilOf() public {}

    function test_penaltyRate() public {
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 123);
        assertEq(123, _protocol.penaltyRate());
    }

    function test_rateModel() public {
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        assertEq(_minterRateModelAddress, _protocol.rateModel());
    }

    function test_pendingRetrievalsOf() public {}

    function test_totalActiveOwedM() public {}

    function test_totalPendingCollateralRetrievalOf() public {}

    function test_totalInactiveOwedM() public {}

    function test_totalOwedM() public {}

    function test_unfrozenTimeOf() public {}

    function test_updateCollateralInterval() public {
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 2000);
        assertEq(2000, _protocol.updateCollateralInterval());
    }

    function test_validatorThreshold() public {}

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    // Impose penalty on minter based on an amount and a rate
    function test__imposePenalty_fixedIndex() public {
        _protocol.override_fixedIndex(); // no compound interest
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 500); // 5%
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 200e18); // 200
        _protocol.setter_totalPrincipalOfActiveOwedM(300e18); // 200 alice + 100 other

        // Expect event
        vm.expectEmit(true, false, false, true, address(_protocolAddress));
        emit IProtocol.PenaltyImposed(_aliceAddress, 5e18);

        _protocol.external_imposePenalty(_aliceAddress, 100e18);

        assertEq(205e18, _protocol.activeOwedMOf(_aliceAddress)); // 200 existing alice + 5 principal
        assertEq(305e18, _protocol.getter_totalPrincipalOfActiveOwedM()); // 200 existing total + 5 principal
    }

    // case A: penaltyBase = 0
    function test__imposePenaltyIfMissedCollateralUpdates_oneMissedInterval_fixedIndex() public {
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount
        _protocol.override_fixedIndex(); // no compunding interest
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 200e18); // 200
        _protocol.setter_totalPrincipalOfActiveOwedM(300e18); // 200 alice + 100 other

        // Penalty Calculation (2 missed intervals)
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days);
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 12
        vm.warp(14 days);

        assertEq(200e18, _protocol.activeOwedMOf(_aliceAddress)); // 200 existing alice + 5 principal
        assertEq(300e18, _protocol.getter_totalPrincipalOfActiveOwedM()); // 200 existing total + 5 principal

        // TODO Stefan continue here
    }

    function test__imposePenaltyIfMissedCollateralUpdates_noMissedInterval_fixedIndex() public {
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount
        _protocol.override_fixedIndex(); // no compunding interest
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 200e18); // 200
        _protocol.setter_totalPrincipalOfActiveOwedM(300e18); // 200 alice + 100 other

        // Penalty Calculation (2 missed intervals)
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days);
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 14 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 14 days); // last penalized on day 12
        vm.warp(14 days);

        vm.recordLogs();
        _protocol.external_imposePenaltyIfMissedCollateralUpdates(_aliceAddress);

        // No event in logs (workaround)
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(0, entries.length);

        // No change in owedM
        assertEq(200e18, _protocol.activeOwedMOf(_aliceAddress)); // 200 existing alice + 5 principal
        assertEq(300e18, _protocol.getter_totalPrincipalOfActiveOwedM()); // 200 existing total + 5 principal
    }

    function test__imposePenaltyIfUndercollateralized() public {}

    function test__repayForActiveMinter() public {}

    function test__repayForInactiveMinter() public {}

    function test__resolvePendingRetrievals() public {}

    function test__updateCollateral() public {}

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function test__getPenaltyBaseAndTimeForMissedCollateralUpdates_fixedIndex() public {
        // SPOG Values
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days); // global update interval = 1 day

        // Amount calculation (current amount + compound interest)
        uint256 _activeOwedM = 100e18;
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, _activeOwedM); // current amount
        _protocol.override_fixedIndex(); // override index calculation

        // Penalty Calculation (2 missed intervals)
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 12
        vm.warp(14 days);

        // if updateInterval_ == 0 --> max(lastUpdate_, penalizedUntil_)
        // if (lastUpdate_ + updateInterval_) > block.timestamp --> return (0, lastUpdate_)
        // if (penalizedUntil_ + updateInterval_) > block.timestamp --> return (0, penalizedUntil_)

        (uint256 penaltyBase_, uint256 penalizedUntil_) = _protocol
            .external_getPenaltyBaseAndTimeForMissedCollateralUpdates(_aliceAddress);
        // 2 missed intervals: day 13, day 14 --> result = 2 * (_activeOwedM);
        assertEq(200e18, penaltyBase_); // _activeOwedM for two days
        assertEq(14 days, penalizedUntil_);
    }

    function test__getPresentValue_fixedIndex() public {
        _protocol.override_fixedIndex(2e18);
        // Calling ontinuousIndexingMath.multiply(principalAmount_, index_)
        assertEq(6e18, _protocol.external_getPresentValue(3e18));
    }

    function test__getPrincipalValue() public {
        _protocol.override_fixedIndex(2e18);
        // Calling ContinuousIndexingMath.divide(presentAmount_, index_);
        assertEq(3e18, _protocol.external_getPrincipalValue(6e18));
    }

    function test__getUpdateCollateralDigest() public {}

    function test__max() public {}

    function test__min() public {}

    function test__minIgnoreZero() public {}

    function test__rate() public {
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        _minterRateModelRate(123);

        assertEq(123, _protocol.external_rate());
    }

    function test__revertIfMinterFrozen() public {}

    function test__revertIfInactiveMinter() public {}

    function test__revertIfNotApprovedValidator() public {}

    function test__revertIfUndercollateralized() public {}

    function test__verifyValidatorSignatures() public {}

    /******************************************************************************************************************\
    |                                           Test Helper                                         |
    \******************************************************************************************************************/

    function _setValue(bytes32 name_, uint256 value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        );
    }

    function _setValue(bytes32 name_, address value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        );
    }

    function _allowList(bytes32 list_, address account_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector, list_, account_),
            abi.encode(true)
        );
    }

    function _denyList(bytes32 list_, address account_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector, list_, account_),
            abi.encode(false)
        );
    }

    function _mTokenTotalSupply(uint256 totalSupply_) private {
        vm.mockCall(_mTokenAddress, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply_));
    }

    function _mTokenNextIndex(uint256 nextIndex_) private {
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IContinuousIndexing.updateIndex.selector),
            abi.encode(nextIndex_)
        );
    }

    function _minterRateModelRate(uint256 minterRate_) private {
        vm.mockCall(_minterRateModelAddress, abi.encodeWithSelector(IRateModel.rate.selector), abi.encode(minterRate_));
    }

    function _setDefaultsWithoutPenalty() private returns (uint256 total_) {
        // default values
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount
        _protocol.override_fixedIndex(); // override index calculation

        // no penalty
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days); // global update interval = 1 day
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 20); // 0.2%
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 14 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 14 days); // last penalized on day 12

        vm.warp(14 days);

        return 100e18;
    }

    function _setDefaultsWithPenalty() private returns (uint256 total_) {
        // default values
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100e18); // current amount
        _protocol.override_fixedIndex(); // override index calculation

        // no penalty
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 days); // global update interval = 1 day
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 20); // 0.2%
        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 12
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 12

        vm.warp(14 days);

        return (100 + 0.4) * 1e18;
    }
}
