// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
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

     uint256 internal _blockTimestamp = 1_000_000_000; 

    function setUp() public {
        // vault 
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.vault.selector),
            abi.encode(_vaultAddress)
        ); 

         vm.warp(_blockTimestamp);

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
        // TODO test _imposePenaltyIfMissedCollateralUpdates first
    }

    function test_cancelMin() public {
        // TODO
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

    function test_deactivateMinter_happy() public {
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 123);
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
    
        _minterRate(20);
        _mTotalSupply(1000);
        _mNextIndex(1); // TODO put sane value here

        _protocol.setter_isActiveMinter(_aliceAddress, true);
        _protocol.setter_collateral(_aliceAddress, 1_000_000_000_000);
        _protocol.setter_lastUpdateInterval(_aliceAddress, 2000);
        //_protocol.setter_lastUpdateTimestamp(_aliceAddress, 333);
        //_protocol.setter_mintProposals(_aliceAddress, 1000);
        //_protocol.setter_penalizedUntil(_aliceAddress, 444);
        //_protocol.setter_activeOwedM(_aliceAddress, 555);
        //_protocol.setter_unfrozenTime(_aliceAddress, 666);

        vm.prank(_bobAddress);
        vm.expectEmit(true, true, false, true, address(_protocolAddress));
        emit IProtocol.MinterDeactivated(_aliceAddress, 0, _bobAddress);

        _protocol.deactivateMinter(_aliceAddress);
        assertFalse(_protocol.isActiveMinter(_aliceAddress));




        // TODO test 
    }

    function test_freezeMinter() public {
    }

    function test_mintM() public {
    }

    function test_proposeMint() public {
    }

    function test_proposeRetrieval() public {
    }

    function test_updateCollateral() public {
    }

    function test_updateIndex() public {
    }

    /******************************************************************************************************************\
    |                                           External View/Pure Functions                                           |
    \******************************************************************************************************************/

    function test_activeOwedMOf_OneYearVanillaIndex() public {
        // current amount * compounded interest
        _protocol.setter_activeOwedM(_aliceAddress, 100 * 1e18); // current amount 100

        // Interest compunding over eine year
        _protocol.setter_latestIndex(1 * 1e18); // 1
        _protocol.setter_latestUpdateTimestamp(0); // converted into seconds
        _protocol.setter_latestRate(1000); // 10%    
        vm.warp(365 days); // one year later

        // see ContinuousIndexingMathTest::test_getContinuousIndex()
        //       100_000_000_000_000_000_000
        //     +  10 517 083 333 333 333 200 for 10% after 1 year
        assertEq(110_517_083_333_333_333_200, _protocol.activeOwedMOf(_aliceAddress));
    }

    function test_activeOwedMOf_SevenDaysVanillaIndex() public {
        // current amount * compounded interest
        _protocol.setter_activeOwedM(_aliceAddress, 100 * 1e18); // current amount 100

        // Interest compunding over eine year
        _protocol.setter_latestIndex(1 * 1e18); // 1
        _protocol.setter_latestUpdateTimestamp(7 days); // converted into seconds
        _protocol.setter_latestRate(200); // 10%    
        vm.warp(14 days); // 7 days later

        // see ContinuousIndexingMathTest::test_getContinuousIndex()
        //       100_000_000_000_000_000_000
        //     +      38_363_521_300_872_800 for 2% after 7 days
        assertEq(100_038_363_521_300_872_800, _protocol.activeOwedMOf(_aliceAddress));
    }


    function test_activeOwedMOf_SevenDaysUpdatedIndex() public {
        // current amount * compounded interest
        _protocol.setter_activeOwedM(_aliceAddress, 100 * 1e18); // current amount 100

        // Interest compunding over eine year
        _protocol.setter_latestIndex(2 * 1e18); // 2
        _protocol.setter_latestUpdateTimestamp(7 days); // converted into seconds
        _protocol.setter_latestRate(200); // 10%    
        vm.warp(14 days); // 7 days later

        // make sure the latest index is used in calculation
        //       100_000_000_000_000_000_000
        //     +      38_363_521_300_872_800 for 2% after 7 days
        assertEq(200_076_727_042_601_745_600, _protocol.activeOwedMOf(_aliceAddress));
    }

    function test_collateralOf() public {
    }

    function test_collateralUpdateDeadlineOf() public {
    }

    function test_excessActiveOwedM() public {
    }

    function test_getMaxAllowedOwedM() public {
    }

    // TODO Holger
    function test_getPenaltyForMissedCollateralUpdates() public {
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 20); // 0.2%
        // See test__getPenaltyBaseAndTimeForMissedCollateralUpdates       
    }

    function test_inactiveOwedMOf() public {
    }

    function test_isActiveMinter() public {
    }

    function test_isMinterApprovedByRegistrar_Allowed() public {
        _allowList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        assertTrue(_protocol.isMinterApprovedByRegistrar(_aliceAddress));
    }

    function test_isMinterApprovedByRegistrar_Denied() public {
        _denyList(SPOGRegistrarReader.MINTERS_LIST, _aliceAddress);

        assertFalse(_protocol.isMinterApprovedByRegistrar(_aliceAddress));
    }

    function test_isValidatorApprovedByRegistrar() public {
    }

    function test_lastUpdateIntervalOf() public {
    }

    function test_lastUpdateOf() public {
    }

    function test_mintDelay() public {
    }

    function test_minterFreezeTime() public {
    }

    function test_minterRate() public {
    }

    function test_mintProposalOf() public {
    }

    function test_mintRatio() public {
    }

    function test_mintTTL() public {
    }

    function test_penalizedUntilOf() public {
    }

    function test_penaltyRate() public {
        _setValue(SPOGRegistrarReader.PENALTY_RATE, 123);
        assertEq(123, _protocol.penaltyRate());
    }

    function test_rateModel() public {
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        assertEq(_minterRateModelAddress, _protocol.rateModel());
    }

    function test_pendingRetrievalsOf() public {
    }

    function test_totalActiveOwedM() public {
    }

    function test_totalPendingCollateralRetrievalOf() public {
    }

    function test_totalInactiveOwedM() public {
    }
    
    function test_totalOwedM() public {
    }

    function test_unfrozenTimeOf() public {
    }

    function test_updateCollateralInterval() public {
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 2000);
        assertEq(2000, _protocol.updateCollateralInterval());
    }

    function test_validatorThreshold() public {
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function test__imposePenalty() public {
    }

    function test__imposePenaltyIfMissedCollateralUpdates() public {
    }

    function test__imposePenaltyIfUndercollateralized() public {
    }

    function test__repayForActiveMinter() public {
    }

    function test__repayForInactiveMinter() public {
    }

    function test__resolvePendingRetrievals() public {
    }

    function test__updateCollateral() public {
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/


    function test__getPenaltyBaseAndTimeForMissedCollateralUpdates() public {
        uint256 updateInterval_ = 1 days;

        uint256 _activeOwedM = 100_038_363_521_300_872_800; // see test_activeOwedMOf_SevenDaysVanillaIndex
        _protocol.setter_activeOwedM(_aliceAddress, 100 * 1e18);
        _protocol.setter_latestIndex(1 * 1e18); 
        _protocol.setter_latestUpdateTimestamp(7 days);
        _protocol.setter_latestRate(200);

        vm.warp(14 days); 

        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, updateInterval_); // global update interval = 1 day
        _protocol.setter_lastUpdateInterval(_aliceAddress, updateInterval_); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 13
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 13

        // if updateInterval_ == 0 --> max(lastUpdate_, penalizedUntil_)
        // if (lastUpdate_ + updateInterval_) > block.timestamp --> return (0, lastUpdate_)
        // if (penalizedUntil_ + updateInterval_) > block.timestamp --> return (0, penalizedUntil_)

         (uint256 penaltyBase_, uint256 penalizedUntil_) = _protocol.external_getPenaltyBaseAndTimeForMissedCollateralUpdates(_aliceAddress);
         // 2 missed intervals: day 13, day 14
         assertEq(2 * _activeOwedM, penaltyBase_);


         console2.logUint(penaltyBase_);
         console2.logUint(penalizedUntil_);
    }



    // function test__getPenaltyBaseAndTimeForMissedCollateralUpdates_Init() public {
    //     uint256 updateInterval_ = 1 days;

    //     //currentIndex() -> 100_038_363_521_300_872_800 - see test_activeOwedMOf_SevenDaysVanillaIndex
    //     _protocol.setter_activeOwedM(_aliceAddress, 100 * 1e18);
    //     _protocol.setter_latestIndex(1 * 1e18); 
    //     _protocol.setter_latestUpdateTimestamp(7 days);
    //     _protocol.setter_latestRate(200);

    //     vm.warp(14 days); 

    //     _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, updateInterval_); // global update interval = 1 day
    //     _protocol.setter_lastUpdateInterval(_aliceAddress, updateInterval_); // minter update interval = 1 day
    //     _protocol.setter_lastUpdateTimestamp(_aliceAddress, 13 days); // last update on day 13
    //     _protocol.setter_penalizedUntil(_aliceAddress, 13 days); // last penalized on day 13


    //     // if updateInterval_ == 0 --> max(lastUpdate_, penalizedUntil_)
    //     // if (lastUpdate_ + updateInterval_) > block.timestamp --> return (0, lastUpdate_)
    //     // if (penalizedUntil_ + updateInterval_) > block.timestamp --> return (0, penalizedUntil_)


    //      (uint256 rpenaltyBase_, uint256 rpenalizedUntil_) = _protocol.external_getPenaltyBaseAndTimeForMissedCollateralUpdates(_aliceAddress);

    //      console2.logUint(rpenaltyBase_);
    //      console2.logUint(rpenalizedUntil_);
    // }



    function test__getPresentValue() public {
        

        // calling ContinuousIndexing._getPresentAmount
        // principalAmount * currentIndex()

        // TODO finish math testing


        //_protocol._getPresentValue(principalValue_);
    }

    function test__getPrincipalValue() public {
    }

    function test__getUpdateCollateralDigest() public {
    }

    function test__max() public {
    }

    function test__min() public {
    }

    function test__minIgnoreZero() public {
    }

    function test__rate() public {
        _setValue(SPOGRegistrarReader.MINTER_RATE_MODEL, _minterRateModelAddress);
        _minterRate(123);

        assertEq(123, _protocol.external_rate());
    }

    function test__revertIfMinterFrozen() public {
    }

    function test__revertIfInactiveMinter() public {
    }

    function test__revertIfNotApprovedValidator() public {
    }

    function test__revertIfUndercollateralized() public {
    }

    function test__verifyValidatorSignatures() public {
    }


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

    function _mTotalSupply(uint256 totalSupply_) private {
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IERC20.totalSupply.selector),
            abi.encode(totalSupply_)
        ); 
    }

    function _mNextIndex(uint256 nextIndex_) private {
        vm.mockCall(
            _mTokenAddress,
            abi.encodeWithSelector(IContinuousIndexing.updateIndex.selector),
            abi.encode(nextIndex_)
        ); 
    }

    function _minterRate(uint256 minterRate_) private {
        vm.mockCall(
            _minterRateModelAddress,
            abi.encodeWithSelector(IRateModel.rate.selector),
            abi.encode(minterRate_)
        ); 
    }




}
