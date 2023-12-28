// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { ContinuousIndexing } from "../src/ContinuousIndexing.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { DigestHelper } from "./utils/DigestHelper.sol";
import { MockMToken, MockRateModel, MockSPOGRegistrar } from "./utils/Mocks.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

// TODO: add tests for `updateIndex` being called.
// TODO: more end state tests of `deactivateMinter`.

contract ProtocolTests is Test {
    uint256 internal constant ONE = 10000;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _spogVault = makeAddr("spogVault");

    address internal _minter1 = makeAddr("minter1");

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralThreshold = 1;

    uint32 internal _updateCollateralInterval = 2000;
    uint32 internal _minterFreezeTime = 1000;
    uint32 internal _mintDelay = 1000;
    uint32 internal _mintTTL = 500;
    uint32 internal _minterRate = 400; // 4%, bps
    uint32 internal _mintRatio = 9000; // 90%, bps
    uint32 internal _penaltyRate = 100; // 1%, bps

    MockMToken internal _mToken;
    MockRateModel internal _minterRateModel;
    MockSPOGRegistrar internal _spogRegistrar;
    ProtocolHarness internal _protocol;

    function setUp() external {
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator2");

        _minterRateModel = new MockRateModel();

        _minterRateModel.setRate(_minterRate);

        _mToken = new MockMToken();

        _spogRegistrar = new MockSPOGRegistrar();

        _spogRegistrar.setVault(_spogVault);

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validator1);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validator2);

        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD,
            _updateCollateralThreshold
        );
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, _mintDelay);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_TTL, _mintTTL);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, _mintRatio);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, address(_minterRateModel));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MISSED_INTERVAL_PENALTY_RATE, _penaltyRate);

        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        _protocol.setActiveMinter(_minter1, true);
        _protocol.setLatestRate(_minterRate); // This can be `protocol.updateIndex()`, but is not necessary.
    }

    function test_updateCollateral() external {
        uint128 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp = uint40(block.timestamp);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IProtocol.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.collateralOf(_minter1), collateral);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(_minter1), _updateCollateralInterval);
        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_protocol.collateralUpdateDeadlineOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_protocol.maxAllowedActiveOwedMOf(_minter1), (collateral * _mintRatio) / ONE);
    }

    function test_updateCollateral_signatureArrayLengthsMismatch() external {
        vm.expectRevert(IProtocol.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](2),
            new uint256[](1),
            new bytes[](1)
        );

        vm.expectRevert(IProtocol.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](1),
            new uint256[](2),
            new bytes[](1)
        );

        vm.expectRevert(IProtocol.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](1),
            new uint256[](1),
            new bytes[](2)
        );
    }

    function test_updateCollateral_staleCollateralUpdate() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 lastUpdateTimestamp = _protocol.collateralUpdateTimestampOf(_minter1);
        uint256 newTimestamp = lastUpdateTimestamp - 1;

        timestamps[0] = newTimestamp;
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            newTimestamp,
            _validator1Pk
        );

        vm.expectRevert(
            abi.encodeWithSelector(IProtocol.StaleCollateralUpdate.selector, newTimestamp, lastUpdateTimestamp)
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_invalidSignatureOrder() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = block.timestamp;

        bytes memory signature1_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator2Pk
        );

        address[] memory validators = new address[](3);
        validators[0] = _validator2;
        validators[1] = _validator2;
        validators[2] = _validator1;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature2_;
        signatures[1] = signature2_;
        signatures[2] = signature1_;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp;

        vm.expectRevert(IProtocol.InvalidSignatureOrder.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = block.timestamp;

        bytes memory signature1_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator2Pk
        );

        (address validator3_, uint256 validator3Pk_) = makeAddrAndKey("validator3");
        bytes memory signature3_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            validator3Pk_
        );

        (address validator4_, uint256 validator4Pk_) = makeAddrAndKey("validator4");
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, validator4_);
        bytes memory signature4_ = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            validator4Pk_
        );

        address[] memory validators = new address[](4);
        validators[0] = _validator2;
        validators[1] = _validator1;
        validators[2] = validator4_;
        validators[3] = validator3_;

        bytes[] memory signatures = new bytes[](4);
        signatures[0] = signature2_;
        signatures[1] = signature1_;
        signatures[2] = signature4_;
        signatures[3] = signature3_;

        uint256[] memory timestamps = new uint256[](4);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp - 1;
        timestamps[3] = timestamp;

        vm.expectRevert(abi.encodeWithSelector(IProtocol.NotEnoughValidSignatures.selector, 2, 3));

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_proposeMint() external {
        uint128 amount = 60e18;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint48 expectedMintId = _protocol.mintNonce() + 1;

        vm.expectEmit();
        emit IProtocol.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint256 mintId = _protocol.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);

        (uint256 mintId_, uint256 timestamp_, address destination_, uint256 amount_) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, mintId);
        assertEq(amount_, amount);
        assertEq(destination_, _alice);
        assertEq(timestamp_, block.timestamp);
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_inactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);

        vm.expectRevert(IProtocol.InactiveMinter.selector);
        vm.prank(_alice);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_proposeMint_undercollateralizedMint() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 100e18, 90e18));

        vm.prank(_minter1);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_mintM() external {
        uint256 amount = 80e18;
        uint48 mintId = 1;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setMintProposalOf(_minter1, mintId, amount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit IProtocol.MintExecuted(mintId);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, uint256 timestamp_, address destination_, uint256 amount_) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertTrue(_protocol.principalOfActiveOwedMOf(_minter1) > 0);

        // TODO: check that mint has been called.
    }

    // TODO: This test name is unclear. What is it specifically testing?
    function test_mintM_outstandingValue() external {
        uint256 mintAmount = 1000000e6;
        uint256 timestamp = block.timestamp;
        uint48 mintId = 1;

        _protocol.setCollateralOf(_minter1, 10000e18);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setMintProposalOf(_minter1, mintId, mintAmount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        uint128 initialActiveOwedM = _protocol.activeOwedMOf(_minter1);
        uint128 initialIndex = _protocol.latestIndex();
        uint128 principalOfActiveOwedM = _protocol.principalOfActiveOwedMOf(_minter1);

        assertEq(initialActiveOwedM, mintAmount + 1 wei);

        vm.warp(timestamp + _mintDelay + 1);

        uint128 indexAfter1Second = ContinuousIndexingMath.multiplyDown(
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                1
            ),
            initialIndex
        );

        uint128 expectedResult = ContinuousIndexingMath.multiplyUp(principalOfActiveOwedM, indexAfter1Second);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult);

        vm.warp(timestamp + _mintDelay + 31_536_000);

        uint128 indexAfter1Year = ContinuousIndexingMath.multiplyDown(
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                31_536_000
            ),
            initialIndex
        );

        expectedResult = ContinuousIndexingMath.multiplyUp(principalOfActiveOwedM, indexAfter1Year);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult);
    }

    function test_mintM_inactiveMinter() external {
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        vm.prank(makeAddr("someInactiveMinter"));
        _protocol.mintM(1);
    }

    function test_mintM_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1); // TODO: replace with harness setter

        vm.expectRevert(IProtocol.FrozenMinter.selector);
        vm.prank(_minter1);
        _protocol.mintM(1);
    }

    function test_mintM_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 activeTimestamp_ = timestamp + _mintDelay;
        uint48 mintId = 1;

        _protocol.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(activeTimestamp_ - 10);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.PendingMintProposal.selector, activeTimestamp_));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 deadline_ = timestamp + _mintDelay + _mintTTL;
        uint48 mintId = 1;

        _protocol.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(deadline_ + 1);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.ExpiredMintProposal.selector, deadline_));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint() external {
        uint48 mintId = 1;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setMintProposalOf(_minter1, mintId, 95e18, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 95e18, 90e18));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint_outdatedCollateral() external {
        uint48 mintId = 1;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp - _updateCollateralInterval);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setMintProposalOf(_minter1, mintId, 95e18, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 95e18, 0));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_invalidMintRequest() external {
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_minter1);
        _protocol.mintM(1);
    }

    function test_mintM_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        uint48 mintId = 1;

        _protocol.setMintProposalOf(_minter1, mintId, amount, timestamp, _alice);

        vm.expectRevert(IProtocol.InvalidMintProposal.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId - 1);
    }

    function test_cancelMint_byValidator() external {
        uint48 mintId = 1;

        _protocol.setMintProposalOf(_minter1, mintId, 100, block.timestamp, _alice);

        vm.expectEmit();
        emit IProtocol.MintCanceled(mintId, _validator1);

        vm.prank(_validator1);
        _protocol.cancelMint(_minter1, mintId);

        (uint256 mintId_, uint256 timestamp, address destination_, uint256 amount_) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp, 0);
    }

    function test_cancelMint_notApprovedValidator() external {
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(makeAddr("someNonApprovedValidator"));
        _protocol.cancelMint(_minter1, 1);
    }

    function test_cancelMint_invalidMintProposal() external {
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _protocol.cancelMint(_minter1, 1);

        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _protocol.cancelMint(_alice, 1);
    }

    function test_freezeMinter() external {
        uint128 amount = 60e18;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint40 frozenUntil = uint40(block.timestamp) + _minterFreezeTime;

        vm.expectEmit();
        emit IProtocol.MinterFrozen(_minter1, frozenUntil);

        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        assertEq(_protocol.frozenUntilOf(_minter1), frozenUntil);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.proposeMint(amount, _alice);

        // fast-forward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        uint48 expectedMintId = _protocol.mintNonce() + 1;

        vm.expectEmit();
        emit IProtocol.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint mintId = _protocol.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);
    }

    function test_freezeMinter_sequence() external {
        uint40 timestamp = uint40(block.timestamp);
        uint40 frozenUntil = timestamp + _minterFreezeTime;

        vm.expectEmit();
        emit IProtocol.MinterFrozen(_minter1, frozenUntil);

        // first freezeMinter
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        vm.warp(timestamp + _minterFreezeTime / 2);

        vm.expectEmit();
        emit IProtocol.MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);

        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);
    }

    function test_freezeMinter_notApprovedValidator() external {
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(_alice);
        _protocol.freezeMinter(_minter1);
    }

    function test_burnM() external {
        uint256 mintAmount = 1000000e18;
        uint48 mintId = 1;

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, 10000000e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        // TODO: Replace entire mint process with harness setters.
        _protocol.setMintProposalOf(_minter1, mintId, mintAmount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit IProtocol.MintExecuted(mintId);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        uint128 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IProtocol.BurnExecuted(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 0);

        // TODO: Check that burn was called.
    }

    function test_burnM_repayHalfOfOutstandingValue() external {
        _protocol.setCollateralOf(_minter1, 1000e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);
        _protocol.setTotalPrincipalOfActiveOwedM(principalOfActiveOwedM);

        uint128 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IProtocol.BurnExecuted(_minter1, activeOwedM / 2, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM / 2);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), principalOfActiveOwedM / 2);

        // TODO: check that burn has been called.

        vm.expectEmit();
        emit IProtocol.BurnExecuted(_minter1, activeOwedM / 2, _bob);

        vm.prank(_bob);
        _protocol.burnM(_minter1, activeOwedM / 2);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 0);

        // TODO: check that burn has been called.
    }

    function test_burnM_notEnoughBalanceToRepay() external {
        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);
        _protocol.setTotalPrincipalOfActiveOwedM(principalOfActiveOwedM);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_updateCollateral_imposePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint128 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IProtocol.PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 60e18 + _protocol.getPrincipalAmountRoundedUp(penalty));
    }

    function test_updateCollateral_imposePenaltyForMissedCollateralUpdates() external {
        uint256 collateral = 100e18;
        uint256 amount = 180e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);
        _protocol.setTotalPrincipalOfActiveOwedM(amount);

        vm.warp(block.timestamp + _updateCollateralInterval - 1);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signatureTimestamp = block.timestamp;
        timestamps[0] = signatureTimestamp;

        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 maxAllowedOwedM = (collateral * _mintRatio) / ONE;
        uint128 expectedPenalty = uint128(((activeOwedM - maxAllowedOwedM) * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IProtocol.PenaltyImposed(_minter1, expectedPenalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(
            _protocol.principalOfActiveOwedMOf(_minter1),
            amount + _protocol.getPrincipalAmountRoundedUp(expectedPenalty)
        );
    }

    function test_updateCollateral_accrueBothPenalties() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 2 * _updateCollateralInterval);

        uint128 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 2 * _penaltyRate) / ONE);

        uint256 newCollateral = 10e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            newCollateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IProtocol.PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(newCollateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 expectedPenalty = (((activeOwedM + penalty) - (newCollateral * _mintRatio) / ONE) * _penaltyRate) / ONE;

        assertEq(
            _protocol.principalOfActiveOwedMOf(_minter1),
            60e18 + _protocol.getPrincipalAmountRoundedUp(penalty + uint128(expectedPenalty))
        );

        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(_minter1), _updateCollateralInterval);
        assertEq(_protocol.penalizedUntilOf(_minter1), signatureTimestamp);
    }

    function test_burnM_imposePenaltyForExpiredCollateralValue() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint128 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IProtocol.PenaltyImposed(_minter1, penalty);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), _protocol.getPrincipalAmountRoundedUp(penalty));
    }

    function test_imposePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 penalizedUntil = _protocol.penalizedUntilOf(_minter1);

        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(penalizedUntil, timestamp + _updateCollateralInterval);

        vm.prank(_alice);
        _protocol.burnM(_minter1, 10e18);

        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_protocol.penalizedUntilOf(_minter1), penalizedUntil);
    }

    function test_imposePenalty_penalizedUntil_reducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        // Change update collateral interval, more frequent updates are required
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        uint256 threeMissedIntervals = _updateCollateralInterval + (2 * _updateCollateralInterval) / 4;
        vm.warp(timestamp + threeMissedIntervals + 10);

        // Burn 1 unit of M and impose penalty for 3 missed intervals
        vm.prank(_alice);
        _protocol.burnM(_minter1, 1);

        uint256 penalizedUntil = _protocol.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(_minter1), _updateCollateralInterval / 4);

        uint256 oneMoreMissedInterval = _updateCollateralInterval / 4;
        vm.warp(block.timestamp + oneMoreMissedInterval);

        // Burn 1 unit of M and impose penalty for 1 more missed interval
        vm.prank(_alice);
        _protocol.burnM(_minter1, 1);

        penalizedUntil = _protocol.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals + oneMoreMissedInterval);
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervals() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervalsDespiteReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        // Change update collateral interval, more frequent updates are required
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        // Minter only expected to update within the previous interval.
        assertEq(penalty, 0);
    }

    function test_getPenaltyForMissedCollateralUpdates_oneMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_oneMissedIntervalDespiteReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        // Change update collateral interval, more frequent updates are required
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        // Minter only expected to update within the previous interval.
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_threeMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (3 * (_protocol.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_moreMissedIntervalDueToReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        // Change update collateral interval, more frequent updates are required
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        // Minter was expected to update within the previous interval. After that deadline, the new interval is imposed,
        // so instead of 2 more missed intervals, since the interval was divided by 4, each of those 2 missed intervals
        // is actually 4 missed intervals. Therefore, 9 missed intervals in total is expected.
        assertEq(penalty, (9 * (_protocol.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_updateCollateralIntervalHasChanged() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);
        _protocol.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Change update collateral interval, more frequent updates are required
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 2);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        // Penalized for first `_updateCollateralInterval` interval
        penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        vm.warp(block.timestamp + _updateCollateralInterval + 10);

        // Penalized for 2 new `_updateCollateralInterval` interval = 3 penalty intervals
        penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (3 * _protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_isActiveMinter() external {
        assertEq(_protocol.isActiveMinter(_minter1), true);
        assertEq(_protocol.isActiveMinter(makeAddr("someMinter")), false);
    }

    function test_activateMinter_xxx() external {
        address minter_ = makeAddr("someMinter");

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, minter_);

        _protocol.setCollateralOf(minter_, 2_000_000);
        _protocol.setLastCollateralUpdateIntervalOf(minter_, 1 days);
        _protocol.setUpdateTimestampOf(minter_, block.timestamp - 4 hours);
        _protocol.setUnfrozenTimeOf(minter_, block.timestamp + 4 days);

        vm.expectEmit();
        emit IProtocol.MinterActivated(minter_, 0, _alice);

        vm.prank(_alice);
        uint128 principalOfActiveOwedM_ = _protocol.activateMinter(minter_);

        assertEq(principalOfActiveOwedM_, 0);

        assertEq(_protocol.internalCollateralOf(minter_), 2_000_000);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(minter_), 1 days);
        assertEq(_protocol.collateralUpdateTimestampOf(minter_), block.timestamp - 4 hours);
        assertEq(_protocol.frozenUntilOf(minter_), block.timestamp + 4 days);
        assertEq(_protocol.isActiveMinter(minter_), true);
        assertEq(_protocol.principalOfActiveOwedMOf(minter_), 0);
        assertEq(_protocol.inactiveOwedMOf(minter_), 0);

        assertEq(_protocol.totalPrincipalOfActiveOwedM(), 0);
        assertEq(_protocol.totalInactiveOwedM(), 0);

        // TODO: check that `updateIndex()` was called.
    }

    function test_activateMinter_previouslyInactive() external {
        address minter_ = makeAddr("someMinter");

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, minter_);

        _protocol.setCollateralOf(minter_, 2_000_000);
        _protocol.setLastCollateralUpdateIntervalOf(minter_, 1 days);
        _protocol.setUpdateTimestampOf(minter_, block.timestamp - 4 hours);
        _protocol.setUnfrozenTimeOf(minter_, block.timestamp + 4 days);
        _protocol.setInactiveOwedMOf(minter_, 1_000_000);
        _protocol.setTotalPendingRetrievalsOf(_minter1, 500_000);

        _protocol.setTotalInactiveOwedM(1_000_000);
        _protocol.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10);

        vm.expectEmit();
        emit IProtocol.MinterActivated(minter_, 909_091, _alice);

        vm.prank(_alice);
        uint128 principalOfActiveOwedM_ = _protocol.activateMinter(minter_);

        assertEq(principalOfActiveOwedM_, 909_091);

        assertEq(_protocol.internalCollateralOf(minter_), 2_000_000);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(minter_), 1 days);
        assertEq(_protocol.collateralUpdateTimestampOf(minter_), block.timestamp - 4 hours);
        assertEq(_protocol.frozenUntilOf(minter_), block.timestamp + 4 days);
        assertEq(_protocol.isActiveMinter(minter_), true);
        assertEq(_protocol.principalOfActiveOwedMOf(minter_), 909_091);
        assertEq(_protocol.inactiveOwedMOf(minter_), 0);
        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), 500_000);

        assertEq(_protocol.totalPrincipalOfActiveOwedM(), 909_091);
        assertEq(_protocol.totalInactiveOwedM(), 0);

        // TODO: check that `updateIndex()` was called.
    }

    function test_activateMinter_notApprovedMinter() external {
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        vm.prank(_alice);
        _protocol.activateMinter(makeAddr("notApprovedMinter"));
    }

    function test_activateMinter_alreadyActivatedMinter() external {
        vm.expectRevert(IProtocol.ActiveMinter.selector);
        vm.prank(_alice);
        _protocol.activateMinter(_minter1);
    }

    function test_deactivateMinter() external {
        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        _protocol.setCollateralOf(_minter1, 2_000_000);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, 1 days);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp - 4 hours);
        _protocol.setUnfrozenTimeOf(_minter1, block.timestamp + 4 days);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 1_000_000);
        _protocol.setTotalPendingRetrievalsOf(_minter1, 500_000);
        _protocol.setPenalizedUntilOf(_minter1, block.timestamp - 4 hours);

        _protocol.setTotalPrincipalOfActiveOwedM(1_000_000);
        _protocol.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10);
        _protocol.setRetrievalNonce(20);

        vm.expectEmit();
        emit IProtocol.MinterDeactivated(_minter1, 1_100_000, _alice);

        vm.prank(_alice);
        uint128 inactiveOwedM = _protocol.deactivateMinter(_minter1);

        assertEq(inactiveOwedM, 1_100_000);

        assertEq(_protocol.internalCollateralOf(_minter1), 2_000_000);
        assertEq(_protocol.lastCollateralUpdateIntervalOf(_minter1), 1 days);
        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), block.timestamp - 4 hours);
        assertEq(_protocol.frozenUntilOf(_minter1), block.timestamp + 4 days);
        assertEq(_protocol.isActiveMinter(_minter1), false);
        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_protocol.inactiveOwedMOf(_minter1), 1_100_000);
        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), 500_000);
        assertEq(_protocol.penalizedUntilOf(_minter1), 0);

        assertEq(_protocol.totalPrincipalOfActiveOwedM(), 0);
        assertEq(_protocol.totalInactiveOwedM(), 1_100_000);

        // TODO: check that `updateIndex()` was called.
    }

    // TODO: Finish
    function test_skip_burn_deactivatedMinter() external {
        uint128 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IProtocol.BurnExecuted(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);

        // TODO: check that `updateIndex()` was called.
    }

    // TODO: Finish
    function test_deactivateMinter_imposePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp - _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);
        _protocol.setTotalPrincipalOfActiveOwedM(mintAmount);

        uint128 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint128 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit IProtocol.MinterDeactivated(_minter1, activeOwedM + penalty, _alice);

        vm.prank(_alice);
        _protocol.deactivateMinter(_minter1);

        // TODO: check that `updateIndex()` was called.
    }

    function test_deactivateMinter_stillApprovedMinter() external {
        vm.expectRevert(IProtocol.StillApprovedMinter.selector);
        _protocol.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_alreadyInactiveMinter() external {
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        _protocol.deactivateMinter(makeAddr("someInactiveMinter"));
    }

    function test_proposeRetrieval() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(2)));

        uint128 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp1 = uint40(block.timestamp);
        uint40 signatureTimestamp2 = signatureTimestamp1 - 10;

        address[] memory validators = new address[](2);
        validators[0] = _validator2;
        validators[1] = _validator1;

        uint256[] memory timestamps = new uint256[](2);
        timestamps[1] = signatureTimestamp1;
        timestamps[0] = signatureTimestamp2;

        bytes[] memory signatures = new bytes[](2);

        signatures[1] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator1Pk
        );

        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator2Pk
        );

        vm.expectEmit();
        emit IProtocol.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp2);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint48 expectedRetrievalId = _protocol.retrievalNonce() + 1;

        vm.expectEmit();
        emit IProtocol.RetrievalCreated(expectedRetrievalId, _minter1, collateral);

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(collateral);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), collateral);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, retrievalId), collateral);
        assertEq(_protocol.maxAllowedActiveOwedMOf(_minter1), 0);

        vm.warp(block.timestamp + 200);

        signatureTimestamp1 = uint40(block.timestamp) - 100;
        signatureTimestamp2 = uint40(block.timestamp) - 50;

        uint256[] memory newRetrievalIds = new uint256[](1);

        newRetrievalIds[0] = retrievalId;

        timestamps[0] = signatureTimestamp1;
        timestamps[1] = signatureTimestamp2;

        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator2Pk
        );

        signatures[1] = _getCollateralUpdateSignature(
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator1Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral / 2, newRetrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), 0);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
        assertEq(_protocol.maxAllowedActiveOwedMOf(_minter1), ((collateral / 2) * _mintRatio) / ONE);
    }

    function test_proposeRetrieval_inactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);

        vm.expectRevert(IProtocol.InactiveMinter.selector);

        vm.prank(_alice);
        _protocol.proposeRetrieval(100);
    }

    function test_proposeRetrieval_undercollateralized() external {
        uint256 collateral = 100e18;

        uint256 principalOfActiveOwedM = (collateral * _mintRatio) / ONE;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);
        _protocol.setTotalPrincipalOfActiveOwedM(principalOfActiveOwedM);

        uint256 retrievalAmount = 10e18;
        uint256 expectedMaxAllowedOwedM = ((collateral - retrievalAmount) * _mintRatio) / ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IProtocol.Undercollateralized.selector,
                _protocol.activeOwedMOf(_minter1),
                expectedMaxAllowedOwedM
            )
        );

        vm.prank(_minter1);
        _protocol.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_RetrievalsExceedCollateral() external {
        uint256 collateral = 100e18;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setTotalPendingRetrievalsOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 retrievalAmount = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IProtocol.RetrievalsExceedCollateral.selector,
                collateral + retrievalAmount,
                collateral
            )
        );

        vm.prank(_minter1);
        _protocol.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_multipleProposals() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setUpdateTimestampOf(_minter1, block.timestamp);
        _protocol.setLastCollateralUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);
        _protocol.setTotalPrincipalOfActiveOwedM(amount);

        uint128 retrievalAmount = 10e18;
        uint48 expectedRetrievalId = _protocol.retrievalNonce() + 1;

        // First retrieval proposal
        vm.expectEmit();
        emit IProtocol.RetrievalCreated(expectedRetrievalId, _minter1, retrievalAmount);

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(retrievalAmount);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, retrievalId), retrievalAmount);

        // Second retrieval proposal
        vm.prank(_minter1);
        uint256 newRetrievalId = _protocol.proposeRetrieval(retrievalAmount);

        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount * 2);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, newRetrievalId), retrievalAmount);

        uint256[] memory retrievalIds = new uint256[](1);
        retrievalIds[0] = newRetrievalId;

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = timestamp;

        bytes[] memory signatures = new bytes[](1);

        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        // Close first retrieval proposal
        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, newRetrievalId), 0);

        retrievalIds[0] = retrievalId;
        validators[0] = _validator1;

        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        timestamps[0] = timestamp;

        // Close second retrieval request
        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.totalPendingCollateralRetrievalsOf(_minter1), 0);
        assertEq(_protocol.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
    }

    function test_updateCollateral_futureTimestamp() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp + 100;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp + 100,
            _validator1Pk
        );

        vm.expectRevert(IProtocol.FutureTimestamp.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_zeroThreshold() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(0)));

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.collateralOf(_minter1), 100);
        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), block.timestamp);
    }

    function test_updateCollateral_someSignaturesAreInvalid() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(1)));

        uint256[] memory retrievalIds = new uint256[](0);

        (address validator3, uint256 validator3Pk) = makeAddrAndKey("validator3");
        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = _validator2;
        validators[2] = validator3;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = block.timestamp;
        timestamps[1] = block.timestamp;
        timestamps[2] = block.timestamp;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = _getCollateralUpdateSignature(
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator1Pk
        ); // valid signature

        signatures[1] = _getCollateralUpdateSignature(
            _minter1,
            200,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator2Pk
        );

        signatures[2] = _getCollateralUpdateSignature(
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            validator3Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.collateralOf(_minter1), 100);
        assertEq(_protocol.collateralUpdateTimestampOf(_minter1), block.timestamp);
    }

    function test_emptyRateModel() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, address(0));

        assertEq(_protocol.rate(), 0);
    }

    function test_readSPOGParameters() external {
        address peter = makeAddr("peter");

        assertEq(_protocol.isMinterApprovedBySPOG(peter), false);
        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, peter);
        assertEq(_protocol.isMinterApprovedBySPOG(peter), true);

        assertEq(_protocol.isValidatorApprovedBySPOG(peter), false);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, peter);
        assertEq(_protocol.isValidatorApprovedBySPOG(peter), true);

        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validator1);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, 8000);
        assertEq(_protocol.mintRatio(), 8000);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);
        assertEq(_protocol.updateCollateralValidatorThreshold(), 3);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 12 * 60 * 60);
        assertEq(_protocol.updateCollateralInterval(), 12 * 60 * 60);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, 2 * 60 * 60);
        assertEq(_protocol.minterFreezeTime(), 2 * 60 * 60);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, 3 * 60 * 60);
        assertEq(_protocol.mintDelay(), 3 * 60 * 60);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_TTL, 4 * 60 * 60);
        assertEq(_protocol.mintTTL(), 4 * 60 * 60);

        MockRateModel minterRateModel = new MockRateModel();
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, address(minterRateModel));
        assertEq(_protocol.rateModel(), address(minterRateModel));

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MISSED_INTERVAL_PENALTY_RATE, 100);
        assertEq(_protocol.missedIntervalPenaltyRate(), 100);
    }

    function test_updateCollateralInterval() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 10);
        assertEq(_protocol.updateCollateralInterval(), 10);
    }

    function test_totalActiveOwedM() external {
        _protocol.setTotalPrincipalOfActiveOwedM(1_000_000);
        assertEq(_protocol.totalActiveOwedM(), 1_000_000);

        _protocol.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10);

        assertEq(_protocol.totalActiveOwedM(), 1_100_000);
    }

    function test_totalInactiveOwedM() external {
        _protocol.setTotalInactiveOwedM(1_000_000);
        assertEq(_protocol.totalInactiveOwedM(), 1_000_000);
    }

    function test_totalOwedM() external {
        _protocol.setTotalInactiveOwedM(500_000);
        _protocol.setTotalPrincipalOfActiveOwedM(1_000_000);
        assertEq(_protocol.totalOwedM(), 1_500_000);

        _protocol.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10);

        assertEq(_protocol.totalOwedM(), 1_600_000);
    }

    function test_activeOwedMOf() external {
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 1_000_000);
        assertEq(_protocol.activeOwedMOf(_minter1), 1_000_000);

        _protocol.setLatestIndex(ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10);

        assertEq(_protocol.activeOwedMOf(_minter1), 1_100_000);
    }

    function test_inactiveOwedMOf() external {
        _protocol.setInactiveOwedMOf(_minter1, 1_000_000);
        assertEq(_protocol.inactiveOwedMOf(_minter1), 1_000_000);
    }

    function test_getMissedCollateralUpdateParameters_zeroNewUpdateInterval() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 365 days, // This does not matter
            lastUpdate_: uint40(block.timestamp) - 48 hours, // This does not matter
            lastPenalizedUntil_: uint40(block.timestamp) - 24 hours, // This does not matter
            newUpdateInterval_: 0
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, block.timestamp);
    }

    function test_getMissedCollateralUpdateParameters_newMinter() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 0,
            lastUpdate_: 0,
            lastPenalizedUntil_: 0,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, block.timestamp + 24 hours);
    }

    function test_getMissedCollateralUpdateParameters_noMissedIntervals() external {
        uint40 missedIntervals_;
        uint40 missedUntil_;

        // Minter with no missed intervals according to their last update and last update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 12 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 25 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(block.timestamp) - 12 hours); // lastUpdate_

        // Minter with no missed intervals according to their last update and new update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 12 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 25 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(block.timestamp) - 12 hours); // lastUpdate_

        // Minter with no missed intervals according to their last penalized until and last update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 25 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 12 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(block.timestamp) - 12 hours); // lastPenalizedUntil_

        // Minter with no missed intervals according to their last penalized until and last update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 25 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 12 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(block.timestamp) - 12 hours); // lastPenalizedUntil_
    }

    function test_getMissedCollateralUpdateParameters_firstMissedIntervals() external {
        uint40 missedIntervals_;
        uint40 missedUntil_;

        // Minter with 1 missed interval according to their last update and last update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 25 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 26 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 1);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_

        // Minter with 1 missed interval according to their last update and new update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 25 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 26 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 1);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_

        // Minter with 1 missed interval according to their last penalized until and last update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 26 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 25 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 1);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_

        // Minter with 1 missed interval according to their last penalized until and new update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 26 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 25 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 1);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_
    }

    function test_getMissedCollateralUpdateParameters_additionalMissedIntervals() external {
        uint40 missedIntervals_;
        uint40 missedUntil_;

        // Minter with 1 missed interval according to their last update and last update interval and 1 missed interval
        // according to the new update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 29 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 30 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 2);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_ + newUpdateInterval_

        // Minter with 1 missed interval according to their last update and new update interval and 1 missed interval
        // according to the new update interval (effectively, 2 missed intervals according to the new update interval).
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 49 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 50 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 2);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastUpdate_ + lastUpdateInterval_ + newUpdateInterval_

        // Minter with 1 missed interval according to their last penalized until and last update interval and 1 missed
        // interval according to the new update interval.
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 24 hours,
            lastUpdate_: uint40(block.timestamp) - 29 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 30 hours,
            newUpdateInterval_: 4 hours
        });

        assertEq(missedIntervals_, 2);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastPenalizedUntil_ + lastUpdateInterval_ + newUpdateInterval_

        // Minter with 1 missed interval according to their last penalized until and new update interval and 1 missed
        // interval according to the new update interval (effectively, 2 missed intervals according to the new update interval).
        (missedIntervals_, missedUntil_) = _protocol.getMissedCollateralUpdateParameters({
            lastUpdateInterval_: 4 hours,
            lastUpdate_: uint40(block.timestamp) - 50 hours,
            lastPenalizedUntil_: uint40(block.timestamp) - 49 hours,
            newUpdateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 2);
        assertEq(missedUntil_, uint40(block.timestamp) - 1 hours); // lastPenalizedUntil_ + lastUpdateInterval_ + newUpdateInterval_
    }

    function _getCollateralUpdateSignature(
        address minter,
        uint256 collateral,
        uint256[] memory retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        return
            _getSignature(
                DigestHelper.getUpdateCollateralDigest(
                    address(_protocol),
                    minter,
                    collateral,
                    retrievalIds,
                    metadataHash,
                    timestamp
                ),
                privateKey
            );
    }

    function _getSignature(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }
}
