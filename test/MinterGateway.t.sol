// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../src/libs/TTGRegistrarReader.sol";

import { IMinterGateway } from "../src/interfaces/IMinterGateway.sol";

import { MockMToken, MockRateModel, MockTTGRegistrar } from "./utils/Mocks.sol";
import { MinterGatewayHarness } from "./utils/MinterGatewayHarness.sol";
import { TestUtils } from "./utils/TestUtils.sol";

// TODO: add tests for `updateIndex` being called.
// TODO: more end state tests of `deactivateMinter`.

contract MinterGatewayTests is TestUtils {
    uint16 internal constant ONE = 10_000;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _ttgVault = makeAddr("ttgVault");

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
    MockTTGRegistrar internal _ttgRegistrar;
    MinterGatewayHarness internal _minterGateway;

    function setUp() external {
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator2");

        _minterRateModel = new MockRateModel();

        _minterRateModel.setRate(_minterRate);

        _mToken = new MockMToken();

        _ttgRegistrar = new MockTTGRegistrar();

        _ttgRegistrar.setVault(_ttgVault);

        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minter1);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator1);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator2);

        _ttgRegistrar.updateConfig(
            TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD,
            _updateCollateralThreshold
        );
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_DELAY, _mintDelay);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_TTL, _mintTTL);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_RATIO, _mintRatio);
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(_minterRateModel));
        _ttgRegistrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, _penaltyRate);

        _minterGateway = new MinterGatewayHarness(address(_ttgRegistrar), address(_mToken));

        _minterGateway.setIsActive(_minter1, true);
        _minterGateway.setLatestRate(_minterRate); // This can be `minterGateway.updateIndex()`, but is not necessary.
    }

    function test_updateCollateral() external {
        uint240 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp = uint40(block.timestamp);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), collateral);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.collateralUpdateDeadlineOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), (collateral * _mintRatio) / ONE);
    }

    function test_updateCollateral_shortSignature() external {
        uint240 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint40 signatureTimestamp = uint40(block.timestamp);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateShortSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), collateral);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.collateralUpdateDeadlineOf(_minter1), signatureTimestamp + _updateCollateralInterval);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), (collateral * _mintRatio) / ONE);
    }

    function test_updateCollateral_inactiveMinter() external {
        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        _minterGateway.setIsActive(_minter1, false);

        vm.prank(_validator1);
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        _minterGateway.updateCollateral(100e18, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_signatureArrayLengthsMismatch() external {
        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](2),
            new uint256[](1),
            new bytes[](1)
        );

        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            100,
            new uint256[](0),
            bytes32(0),
            new address[](1),
            new uint256[](2),
            new bytes[](1)
        );

        vm.expectRevert(IMinterGateway.SignatureArrayLengthsMismatch.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
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
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 lastUpdateTimestamp = _minterGateway.collateralUpdateTimestampOf(_minter1);
        uint256 newTimestamp = lastUpdateTimestamp - 1;

        timestamps[0] = newTimestamp;
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            newTimestamp,
            _validator1Pk
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMinterGateway.StaleCollateralUpdate.selector, newTimestamp, lastUpdateTimestamp)
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_invalidSignatureOrder() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = block.timestamp;

        bytes memory signature1_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            address(_minterGateway),
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

        vm.expectRevert(IMinterGateway.InvalidSignatureOrder.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = block.timestamp;

        bytes memory signature1_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        bytes memory signature2_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator2Pk
        );

        (address validator3_, uint256 validator3Pk_) = makeAddrAndKey("validator3");
        bytes memory signature3_ = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            validator3Pk_
        );

        (address validator4_, uint256 validator4Pk_) = makeAddrAndKey("validator4");
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, validator4_);
        bytes memory signature4_ = _getCollateralUpdateSignature(
            address(_minterGateway),
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

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.NotEnoughValidSignatures.selector, 2, 3));

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_proposeMint() external {
        uint240 amount = 60e18;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        uint48 expectedMintId = _minterGateway.mintNonce() + 1;

        vm.expectEmit();
        emit IMinterGateway.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint256 mintId = _minterGateway.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);

        (uint256 mintId_, uint256 timestamp_, address destination_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, mintId);
        assertEq(amount_, amount);
        assertEq(destination_, _alice);
        assertEq(timestamp_, block.timestamp);
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_inactiveMinter() external {
        _minterGateway.setIsActive(_minter1, false);

        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        vm.prank(_alice);
        _minterGateway.proposeMint(100e18, _alice);
    }

    function test_proposeMint_undercollateralizedMint() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 100e18, 90e18));

        vm.prank(_minter1);
        _minterGateway.proposeMint(100e18, _alice);
    }

    function test_mintM() external {
        uint256 amount = 80e18;
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(mintId);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, uint256 timestamp_, address destination_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertTrue(_minterGateway.principalOfActiveOwedMOf(_minter1) > 0); // TODO: use rawOwedMOf

        // TODO: Check that mint has been called.
    }

    // TODO: This test name is unclear. What is it specifically testing?
    function test_mintM_outstandingValue() external {
        uint256 mintAmount = 1000000e6;
        uint256 timestamp = block.timestamp;
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 10000e18);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);

        _minterGateway.setMintProposalOf(_minter1, mintId, mintAmount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);

        uint256 initialActiveOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint128 initialIndex = _minterGateway.latestIndex();
        uint112 principalOfActiveOwedM = _minterGateway.principalOfActiveOwedMOf(_minter1); // TODO: use rawOwedMOf

        assertEq(initialActiveOwedM, mintAmount + 1 wei); // TODO: Assert rawOwedMOf.

        vm.warp(timestamp + _mintDelay + 1);

        uint128 indexAfter1Second = ContinuousIndexingMath.multiplyIndices(
            initialIndex,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                1
            )
        );

        uint240 expectedResult = ContinuousIndexingMath.multiplyUp(principalOfActiveOwedM, indexAfter1Second);

        assertEq(_minterGateway.activeOwedMOf(_minter1), expectedResult);

        vm.warp(timestamp + _mintDelay + 31_536_000);

        uint128 indexAfter1Year = ContinuousIndexingMath.multiplyIndices(
            initialIndex,
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(uint32(_minterRate)),
                31_536_000
            )
        );

        expectedResult = ContinuousIndexingMath.multiplyUp(principalOfActiveOwedM, indexAfter1Year);

        assertEq(_minterGateway.activeOwedMOf(_minter1), expectedResult);
    }

    function test_mintM_inactiveMinter() external {
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);

        vm.prank(makeAddr("someInactiveMinter"));
        _minterGateway.mintM(1);
    }

    function test_mintM_frozenMinter() external {
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1); // TODO: replace with harness setter

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.mintM(1);
    }

    function test_mintM_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 activeTimestamp_ = timestamp + _mintDelay;
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(activeTimestamp_ - 10);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.PendingMintProposal.selector, activeTimestamp_));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 deadline_ = timestamp + _mintDelay + _mintTTL;
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, timestamp, _alice);

        vm.warp(deadline_ + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.ExpiredMintProposal.selector, deadline_));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint() external {
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        _minterGateway.setMintProposalOf(_minter1, mintId, 95e18, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 95e18, 90e18));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint_outdatedCollateral() external {
        uint48 mintId = 1;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp - _updateCollateralInterval);

        _minterGateway.setMintProposalOf(_minter1, mintId, 95e18, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IMinterGateway.Undercollateralized.selector, 95e18, 0));

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);
    }

    function test_mintM_invalidMintRequest() external {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_minter1);
        _minterGateway.mintM(1);
    }

    function test_mintM_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, amount, timestamp, _alice);

        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId - 1);
    }

    function test_cancelMint_byValidator() external {
        uint48 mintId = 1;

        _minterGateway.setMintProposalOf(_minter1, mintId, 100, block.timestamp, _alice);

        vm.expectEmit();
        emit IMinterGateway.MintCanceled(mintId, _validator1);

        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, mintId);

        (uint256 mintId_, uint256 timestamp, address destination_, uint256 amount_) = _minterGateway.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp, 0);
    }

    function test_cancelMint_notApprovedValidator() external {
        vm.expectRevert(IMinterGateway.NotApprovedValidator.selector);
        vm.prank(makeAddr("someNonApprovedValidator"));
        _minterGateway.cancelMint(_minter1, 1);
    }

    function test_cancelMint_invalidMintProposal() external {
        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _minterGateway.cancelMint(_minter1, 1);

        vm.expectRevert(IMinterGateway.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _minterGateway.cancelMint(_alice, 1);
    }

    // TODO: This test should just use test the effects of freezeMinter, another test should check that a frozen minter
    //       cannot proposeMint/mint.
    function test_freezeMinter() external {
        uint240 amount = 60e18;

        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        uint40 frozenUntil = uint40(block.timestamp) + _minterFreezeTime;

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil);

        assertEq(_minterGateway.isFrozenMinter(_minter1), false);

        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        assertEq(_minterGateway.isFrozenMinter(_minter1), true);
        assertEq(_minterGateway.frozenUntilOf(_minter1), frozenUntil);

        vm.expectRevert(IMinterGateway.FrozenMinter.selector);

        vm.prank(_minter1);
        _minterGateway.proposeMint(amount, _alice);

        // fast-forward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        uint48 expectedMintId = _minterGateway.mintNonce() + 1;

        // TODO: This new proposeMint should not be part of this test
        vm.expectEmit();
        emit IMinterGateway.MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint mintId = _minterGateway.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);
    }

    function test_freezeMinter_sequence() external {
        uint40 timestamp = uint40(block.timestamp);
        uint40 frozenUntil = timestamp + _minterFreezeTime;

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil);

        // first freezeMinter
        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);

        vm.warp(timestamp + _minterFreezeTime / 2);

        vm.expectEmit();
        emit IMinterGateway.MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);

        vm.prank(_validator1);
        _minterGateway.freezeMinter(_minter1);
    }

    function test_freezeMinter_notApprovedValidator() external {
        vm.expectRevert(IMinterGateway.NotApprovedValidator.selector);
        vm.prank(_alice);
        _minterGateway.freezeMinter(_minter1);
    }

    function test_burnM() external {
        uint256 mintAmount = 1000000e18;
        uint48 mintId = 1;

        // initiate harness functions
        _minterGateway.setCollateralOf(_minter1, 10000000e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        // TODO: Replace entire mint process with harness setters.
        _minterGateway.setMintProposalOf(_minter1, mintId, mintAmount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit IMinterGateway.MintExecuted(mintId);

        vm.prank(_minter1);
        _minterGateway.mintM(mintId);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0); // TODO: use rawOwedMOf

        // TODO: check that `updateIndex()` was called.
        // TODO: Check that burn was called.
    }

    function test_burnM_repayHalfOfOutstandingValue() external {
        _minterGateway.setCollateralOf(_minter1, 1000e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);

        uint256 principalOfActiveOwedM = 100e18;

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM);
        _minterGateway.setTotalPrincipalOfActiveOwedM(principalOfActiveOwedM);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, activeOwedM / 2, _alice);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), principalOfActiveOwedM / 2); // TODO: use rawOwedMOf

        // TODO: Check that burn has been called.
        // TODO: check that `updateIndex()` was called.

        vm.expectEmit();
        emit IMinterGateway.BurnExecuted(_minter1, activeOwedM / 2, _bob);

        vm.prank(_bob);
        _minterGateway.burnM(_minter1, activeOwedM / 2);

        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0); // TODO: use rawOwedMOf

        // TODO: Check that burn has been called.
        // TODO: check that `updateIndex()` was called.
    }

    function test_burnM_notEnoughBalanceToRepay() external {
        uint256 principalOfActiveOwedM = 100e18;

        _minterGateway.setRawOwedMOf(_minter1, principalOfActiveOwedM);

        uint256 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);

        // TODO: check that `updateIndex()` was called.
    }

    function test_updateCollateral_imposePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            60e18 + _minterGateway.getPrincipalAmountRoundedUp(penalty)
        );
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
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        _minterGateway.setRawOwedMOf(_minter1, amount);
        _minterGateway.setTotalPrincipalOfActiveOwedM(amount);

        vm.warp(block.timestamp + _updateCollateralInterval - 1);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signatureTimestamp = block.timestamp;
        timestamps[0] = signatureTimestamp;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint256 maxAllowedOwedM = (collateral * _mintRatio) / ONE;
        uint240 expectedPenalty = uint240(((activeOwedM - maxAllowedOwedM) * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, expectedPenalty);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.activeOwedMOf(_minter1), activeOwedM + expectedPenalty); // TODO: Assert rawOfOwedM.
    }

    function test_updateCollateral_accrueBothPenalties() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 2 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 2 * _penaltyRate) / ONE);

        uint240 newCollateral = 10e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            newCollateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(newCollateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint240 expectedPenalty = (((activeOwedM + penalty) - (newCollateral * _mintRatio) / ONE) * _penaltyRate) / ONE;

        assertEq(_minterGateway.activeOwedMOf(_minter1), activeOwedM + penalty + expectedPenalty); // TODO: Assert rawOfOwedM.

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), signatureTimestamp);
    }

    function test_burnM_imposePenaltyForExpiredCollateralValue() external {
        _minterGateway.setCollateralOf(_minter1, 100e18);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        vm.expectEmit();
        emit IMinterGateway.PenaltyImposed(_minter1, penalty);

        vm.prank(_alice);
        _minterGateway.burnM(_minter1, activeOwedM);

        assertEq(
            _minterGateway.principalOfActiveOwedMOf(_minter1),
            _minterGateway.getPrincipalAmountRoundedUp(penalty)
        );

        // TODO: check that `updateIndex()` was called.
    }

    function test_imposePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 lastUpdateTimestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, lastUpdateTimestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setTotalPrincipalOfActiveOwedM(60e18);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        vm.warp(lastUpdateTimestamp + _updateCollateralInterval + 10);

        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(penalizedUntil, lastUpdateTimestamp + _updateCollateralInterval);

        // TODO: Burn should not be part of this test.
        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 10e18);

        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), signatureTimestamp);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), penalizedUntil);
    }

    function test_imposePenalty_penalizedUntil_reducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);
        _minterGateway.setTotalPrincipalOfActiveOwedM(60e18);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        uint256 threeMissedIntervals = _updateCollateralInterval + (2 * _updateCollateralInterval) / 4;
        vm.warp(timestamp + threeMissedIntervals + 10);

        // Burn 1 unit of M and impose penalty for 3 missed intervals
        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 1);

        uint256 penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals);

        uint256 oneMoreMissedInterval = _updateCollateralInterval / 4;
        vm.warp(block.timestamp + oneMoreMissedInterval);

        // Burn 1 unit of M and impose penalty for 1 more missed interval
        vm.prank(_alice);
        _minterGateway.burnM(_minter1, 1);

        penalizedUntil = _minterGateway.penalizedUntilOf(_minter1);
        assertEq(penalizedUntil, timestamp + threeMissedIntervals + oneMoreMissedInterval);
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervals() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);
    }

    function test_getPenaltyForMissedCollateralUpdates_oneMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_threeMissedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (3 * (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_moreMissedIntervalsDueToReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 4);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);

        // Minter was expected to update within the previous interval. After that deadline, the new interval is imposed,
        // so instead of 2 more missed intervals, since the interval was divided by 4, each of those 2 missed intervals
        // is actually 4 missed intervals. Therefore, 9 missed intervals in total is expected.
        assertEq(penalty, (12 * (_minterGateway.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_updateCollateralIntervalHasChanged() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, timestamp);
        _minterGateway.setRawOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Change update collateral interval, more frequent updates are required
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval / 2);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        // Penalized for first `_updateCollateralInterval` interval
        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (2 * _minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);

        vm.warp(block.timestamp + _updateCollateralInterval + 10);

        // Penalized for 2 new `_updateCollateralInterval` interval = 3 penalty intervals
        penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (4 * _minterGateway.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_isActiveMinter() external {
        _minterGateway.setIsActive(_minter1, false);
        assertEq(_minterGateway.isActiveMinter(_minter1), false);

        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit IMinterGateway.MinterActivated(_minter1, _alice);

        vm.prank(_alice);
        _minterGateway.activateMinter(_minter1);

        assertEq(_minterGateway.isActiveMinter(_minter1), true);
    }

    function test_activateMinter_notApprovedMinter() external {
        vm.expectRevert(IMinterGateway.NotApprovedMinter.selector);
        vm.prank(_alice);
        _minterGateway.activateMinter(makeAddr("notApprovedMinter"));
    }

    function test_activateMinter_deactivatedMinter() external {
        _minterGateway.setIsDeactivated(_minter1, true);

        vm.expectRevert(IMinterGateway.DeactivatedMinter.selector);
        vm.prank(_alice);
        _minterGateway.activateMinter(_minter1);
    }

    function test_deactivateMinter() external {
        _ttgRegistrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        _minterGateway.setCollateralOf(_minter1, 2_000_000);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp - 4 hours);
        _minterGateway.setUnfrozenTimeOf(_minter1, block.timestamp + 4 days);
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        _minterGateway.setTotalPendingRetrievalsOf(_minter1, 500_000);
        _minterGateway.setPenalizedUntilOf(_minter1, block.timestamp - 4 hours);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp - _updateCollateralInterval + 10);

        _minterGateway.setTotalPrincipalOfActiveOwedM(1_000_000);
        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        vm.expectEmit();
        emit IMinterGateway.MinterDeactivated(_minter1, 1_100_000, _alice);

        vm.prank(_alice);
        uint240 inactiveOwedM = _minterGateway.deactivateMinter(_minter1);

        assertEq(inactiveOwedM, 1_100_000);

        assertEq(_minterGateway.internalCollateralOf(_minter1), 0);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), 0);
        assertEq(_minterGateway.frozenUntilOf(_minter1), 0);
        assertEq(_minterGateway.isActiveMinter(_minter1), false);
        assertEq(_minterGateway.isDeactivatedMinter(_minter1), true);
        assertEq(_minterGateway.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_minterGateway.inactiveOwedMOf(_minter1), 1_100_000);
        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), 0);
        assertEq(_minterGateway.penalizedUntilOf(_minter1), 0);

        assertEq(_minterGateway.rawOwedMOf(_minter1), 1_100_000);
        assertEq(_minterGateway.totalInactiveOwedM(), 1_100_000);

        // TODO: check that `updateIndex()` was called.
    }

    function test_deactivateMinter_imposePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _minterGateway.setCollateralOf(_minter1, mintAmount * 2);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp - _updateCollateralInterval);
        _minterGateway.setRawOwedMOf(_minter1, mintAmount);
        _minterGateway.setTotalPrincipalOfActiveOwedM(mintAmount);

        uint240 activeOwedM = _minterGateway.activeOwedMOf(_minter1);
        uint240 penalty = _minterGateway.getPenaltyForMissedCollateralUpdates(_minter1);

        _ttgRegistrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit IMinterGateway.MinterDeactivated(_minter1, activeOwedM + penalty, _alice);

        vm.prank(_alice);
        _minterGateway.deactivateMinter(_minter1);

        // TODO: check that `updateIndex()` was called.
    }

    function test_deactivateMinter_stillApprovedMinter() external {
        vm.expectRevert(IMinterGateway.StillApprovedMinter.selector);
        vm.prank(_alice);
        _minterGateway.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_alreadyInactiveMinter() external {
        vm.expectRevert(IMinterGateway.InactiveMinter.selector);
        vm.prank(_alice);
        _minterGateway.deactivateMinter(makeAddr("someInactiveMinter"));
    }

    function test_proposeRetrieval() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(2)));

        uint240 collateral = 100;
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
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator1Pk
        );

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator2Pk
        );

        vm.expectEmit();
        emit IMinterGateway.CollateralUpdated(_minter1, collateral, 0, bytes32(0), signatureTimestamp2);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint48 expectedRetrievalId = _minterGateway.retrievalNonce() + 1;

        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId, _minter1, collateral);

        vm.prank(_minter1);
        uint256 retrievalId = _minterGateway.proposeRetrieval(collateral);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), collateral);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), collateral);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), 0);

        vm.warp(block.timestamp + 200);

        signatureTimestamp1 = uint40(block.timestamp) - 100;
        signatureTimestamp2 = uint40(block.timestamp) - 50;

        uint256[] memory newRetrievalIds = new uint256[](1);

        newRetrievalIds[0] = retrievalId;

        timestamps[0] = signatureTimestamp1;
        timestamps[1] = signatureTimestamp2;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator2Pk
        );

        signatures[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            signatureTimestamp2,
            _validator1Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(
            collateral / 2,
            newRetrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
        assertEq(_minterGateway.maxAllowedActiveOwedMOf(_minter1), ((collateral / 2) * _mintRatio) / ONE);
    }

    function test_proposeRetrieval_inactiveMinter() external {
        _minterGateway.setIsActive(_minter1, false);

        vm.expectRevert(IMinterGateway.InactiveMinter.selector);

        vm.prank(_alice);
        _minterGateway.proposeRetrieval(100);
    }

    function test_proposeRetrieval_undercollateralized() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setRawOwedMOf(_minter1, (collateral * _mintRatio) / ONE);

        uint256 retrievalAmount = 10e18;
        uint256 expectedMaxAllowedOwedM = ((collateral - retrievalAmount) * _mintRatio) / ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IMinterGateway.Undercollateralized.selector,
                _minterGateway.activeOwedMOf(_minter1),
                expectedMaxAllowedOwedM
            )
        );

        vm.prank(_minter1);
        _minterGateway.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_RetrievalsExceedCollateral() external {
        uint256 collateral = 100e18;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setTotalPendingRetrievalsOf(_minter1, collateral);

        uint256 retrievalAmount = 10e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinterGateway.RetrievalsExceedCollateral.selector,
                collateral + retrievalAmount,
                collateral
            )
        );

        vm.prank(_minter1);
        _minterGateway.proposeRetrieval(retrievalAmount);
    }

    function test_proposeRetrieval_multipleProposals() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _minterGateway.setCollateralOf(_minter1, collateral);
        _minterGateway.setUpdateTimestampOf(_minter1, block.timestamp);
        _minterGateway.setRawOwedMOf(_minter1, amount);
        _minterGateway.setTotalPrincipalOfActiveOwedM(amount);

        uint240 retrievalAmount = 10e18;
        uint48 expectedRetrievalId = _minterGateway.retrievalNonce() + 1;

        // First retrieval proposal
        vm.expectEmit();
        emit IMinterGateway.RetrievalCreated(expectedRetrievalId, _minter1, retrievalAmount);

        vm.prank(_minter1);
        uint256 retrievalId = _minterGateway.proposeRetrieval(retrievalAmount);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), retrievalAmount);

        // Second retrieval proposal
        vm.prank(_minter1);
        uint256 newRetrievalId = _minterGateway.proposeRetrieval(retrievalAmount);

        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount * 2);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId), retrievalAmount);

        uint256[] memory retrievalIds = new uint256[](1);
        retrievalIds[0] = newRetrievalId;

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = timestamp;

        bytes[] memory signatures = new bytes[](1);

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );

        // Close first retrieval proposal
        vm.prank(_minter1);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), retrievalAmount);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, newRetrievalId), 0);

        retrievalIds[0] = retrievalId;
        validators[0] = _validator1;

        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
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
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.totalPendingCollateralRetrievalsOf(_minter1), 0);
        assertEq(_minterGateway.pendingCollateralRetrievalOf(_minter1, retrievalId), 0);
    }

    function test_updateCollateral_futureTimestamp() external {
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp + 100;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp + 100,
            _validator1Pk
        );

        vm.expectRevert(IMinterGateway.FutureTimestamp.selector);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_zeroThreshold() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(0)));

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), 100);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), block.timestamp);
    }

    function test_updateCollateral_someSignaturesAreInvalid() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, bytes32(uint256(1)));

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
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator1Pk
        ); // valid signature

        signatures[1] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            200,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            _validator2Pk
        );

        signatures[2] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minter1,
            100,
            retrievalIds,
            bytes32(0),
            block.timestamp,
            validator3Pk
        );

        vm.prank(_minter1);
        _minterGateway.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_minterGateway.collateralOf(_minter1), 100);
        assertEq(_minterGateway.collateralUpdateTimestampOf(_minter1), block.timestamp);
    }

    function test_emptyRateModel() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(0));

        assertEq(_minterGateway.rate(), 0);
    }

    function test_totalActiveOwedM() external {
        _minterGateway.setTotalPrincipalOfActiveOwedM(1_000_000);
        assertEq(_minterGateway.totalActiveOwedM(), 1_000_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.totalActiveOwedM(), 1_100_000);
    }

    function test_totalInactiveOwedM() external {
        _minterGateway.setTotalInactiveOwedM(1_000_000);
        assertEq(_minterGateway.totalInactiveOwedM(), 1_000_000);
    }

    function test_totalOwedM() external {
        _minterGateway.setTotalInactiveOwedM(500_000);
        _minterGateway.setTotalPrincipalOfActiveOwedM(1_000_000);
        assertEq(_minterGateway.totalOwedM(), 1_500_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.totalOwedM(), 1_600_000);
    }

    function test_activeOwedMOf() external {
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        assertEq(_minterGateway.activeOwedMOf(_minter1), 1_000_000);

        _minterGateway.setLatestIndex(
            ContinuousIndexingMath.EXP_SCALED_ONE + ContinuousIndexingMath.EXP_SCALED_ONE / 10
        );

        assertEq(_minterGateway.activeOwedMOf(_minter1), 1_100_000);
    }

    function test_inactiveOwedMOf() external {
        _minterGateway.setRawOwedMOf(_minter1, 1_000_000);
        _minterGateway.setIsActive(_minter1, false);

        assertEq(_minterGateway.inactiveOwedMOf(_minter1), 1_000_000);
    }

    function test_getMissedCollateralUpdateParameters_zeroNewUpdateInterval() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _minterGateway.getMissedCollateralUpdateParameters({
            lastUpdateTimestamp_: uint40(block.timestamp) - 48 hours, // This does not matter
            lastPenalizedUntil_: uint40(block.timestamp) - 24 hours, // This does not matter
            updateInterval_: 0
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, uint40(block.timestamp) - 24 hours);
    }

    function test_getMissedCollateralUpdateParameters_newMinter() external {
        (uint40 missedIntervals_, uint40 missedUntil_) = _minterGateway.getMissedCollateralUpdateParameters({
            lastUpdateTimestamp_: 0,
            lastPenalizedUntil_: 0,
            updateInterval_: 24 hours
        });

        assertEq(missedIntervals_, 0);
        assertEq(missedUntil_, 0);
    }

    function test_readTTGParameters() external {
        address peter = makeAddr("peter");

        assertEq(_minterGateway.isMinterApprovedByTTG(peter), false);
        _ttgRegistrar.addToList(TTGRegistrarReader.MINTERS_LIST, peter);
        assertEq(_minterGateway.isMinterApprovedByTTG(peter), true);

        assertEq(_minterGateway.isValidatorApprovedByTTG(peter), false);
        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, peter);
        assertEq(_minterGateway.isValidatorApprovedByTTG(peter), true);

        _ttgRegistrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validator1);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_RATIO, 8000);
        assertEq(_minterGateway.mintRatio(), 8000);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 3);
        assertEq(_minterGateway.updateCollateralValidatorThreshold(), 3);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 12 * 60 * 60);
        assertEq(_minterGateway.updateCollateralInterval(), 12 * 60 * 60);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_FREEZE_TIME, 2 * 60 * 60);
        assertEq(_minterGateway.minterFreezeTime(), 2 * 60 * 60);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_DELAY, 3 * 60 * 60);
        assertEq(_minterGateway.mintDelay(), 3 * 60 * 60);

        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINT_TTL, 4 * 60 * 60);
        assertEq(_minterGateway.mintTTL(), 4 * 60 * 60);

        MockRateModel minterRateModel = new MockRateModel();
        _ttgRegistrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, address(minterRateModel));
        assertEq(_minterGateway.rateModel(), address(minterRateModel));

        _ttgRegistrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, 100);
        assertEq(_minterGateway.penaltyRate(), 100);
    }

    function test_updateCollateralInterval() external {
        _ttgRegistrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 10);
        assertEq(_minterGateway.updateCollateralInterval(), 10);
    }
}
