// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { DigestHelper } from "./utils/DigestHelper.sol";
import { MockMToken, MockRateModel, MockSPOGRegistrar } from "./utils/Mocks.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

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
    uint256 internal _updateCollateralInterval = 2000;
    uint256 internal _minterFreezeTime = 1000;
    uint256 internal _mintDelay = 1000;
    uint256 internal _mintTTL = 500;
    uint256 internal _minterRate = 400; // 4%, bps
    uint256 internal _mintRatio = 9000; // 90%, bps
    uint256 internal _penaltyRate = 100; // 1%, bps

    MockMToken internal _mToken;
    MockRateModel internal _minterRateModel;
    MockSPOGRegistrar internal _spogRegistrar;
    ProtocolHarness internal _protocol;

    event CollateralUpdated(
        address indexed minter,
        uint256 collateral,
        uint256[] indexed retrievalIds,
        bytes32 indexed metadataHash,
        uint256 timestamp
    );

    event MintProposed(uint256 indexed mintId, address indexed minter, uint256 amount, address indexed destination);
    event MintExecuted(uint256 indexed mintId);
    event MintCanceled(uint256 indexed mintId, address indexed canceller);

    event MinterActivated(address indexed minter, address indexed caller);
    event MinterDeactivated(address indexed minter, uint256 owedM, address indexed caller);
    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event BurnExecuted(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyImposed(address indexed minter, uint256 amount);

    event RetrievalCreated(uint256 indexed retrievalId, address indexed minter, uint256 amount);

    // IERC20 events
    event Transfer(address indexed account, address indexed recipient, uint256 amount);

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
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            _updateCollateralThreshold
        );
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateCollateralInterval);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, _mintDelay);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_TTL, _mintTTL);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, _mintRatio);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, address(_minterRateModel));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.PENALTY_RATE, _penaltyRate);

        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        _protocol.activateMinter(_minter1);
        _protocol.setLatestRate(_minterRate); // This can be `protocol.updateIndex()`, but is not necessary.
    }

    function test_updateCollateral() external {
        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 signatureTimestamp = block.timestamp;

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
        emit CollateralUpdated(_minter1, collateral, retrievalIds, bytes32(0), signatureTimestamp);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.collateralOf(_minter1), collateral);
        assertEq(_protocol.lastUpdateIntervalOf(_minter1), _updateCollateralInterval);
        assertEq(_protocol.lastUpdateOf(_minter1), signatureTimestamp);
    }

    function test_updateCollateral_InactiveMinter() external {
        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        _protocol.setActiveMinter(_minter1, false);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.InactiveMinter.selector);
        _protocol.updateCollateral(100e18, retrievalIds, bytes32(0), validators, timestamps, signatures);
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

        uint256 lastUpdateTimestamp = _protocol.lastUpdateOf(_minter1);
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

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD, 3);

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
        validators[0] = _validator1;
        validators[1] = _validator2;
        validators[2] = _validator2;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature1_;
        signatures[1] = signature2_;
        signatures[2] = signature2_;

        uint256[] memory timestamps = new uint256[](3);
        timestamps[0] = timestamp;
        timestamps[1] = timestamp;
        timestamps[2] = timestamp;

        vm.expectRevert(IProtocol.InvalidSignatureOrder.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_proposeMint() external {
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 expectedMintId = _protocol.getMintId(_minter1, amount, _alice, _protocol.mintNonce() + 1);

        vm.expectEmit();
        emit MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint256 mintId = _protocol.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);

        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp_) = _protocol.mintProposalOf(
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

    function test_proposeMint_InactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);

        vm.expectRevert(IProtocol.InactiveMinter.selector);
        vm.prank(_alice);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_proposeMint_undercollateralizedMint() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 100e18, 90e18));

        vm.prank(_minter1);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_mintM() external {
        uint256 amount = 80e18;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit MintExecuted(mintId);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp_) = _protocol.mintProposalOf(
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

        _protocol.setCollateralOf(_minter1, 10000e18);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        uint256 initialActiveOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 initialIndex = _protocol.latestIndex();
        uint256 principalOfActiveOwedM = _protocol.principalOfActiveOwedMOf(_minter1);

        assertEq(initialActiveOwedM + 1, mintAmount, "a");

        vm.warp(timestamp + _mintDelay + 1);

        uint256 indexAfter1Second = ContinuousIndexingMath.multiply(
            ContinuousIndexingMath.getContinuousIndex(ContinuousIndexingMath.convertFromBasisPoints(_minterRate), 1),
            initialIndex
        );

        uint256 expectedResult = ContinuousIndexingMath.multiply(principalOfActiveOwedM, indexAfter1Second);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult, "b");

        vm.warp(timestamp + _mintDelay + 31_536_000);

        uint256 indexAfter1Year = ContinuousIndexingMath.multiply(
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_minterRate),
                31_536_000
            ),
            initialIndex
        );

        expectedResult = ContinuousIndexingMath.multiply(principalOfActiveOwedM, indexAfter1Year);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult, "c");
    }

    function test_mintM_InactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, _alice);

        vm.expectRevert(IProtocol.InactiveMinter.selector);

        vm.prank(_bob);
        _protocol.mintM(mintId);
    }

    function test_mintM_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, _minter1);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, _alice);
        uint256 activeTimestamp_ = timestamp + _mintDelay;

        vm.warp(activeTimestamp_ - 10);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.PendingMintProposal.selector, activeTimestamp_));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, _alice);
        uint256 deadline_ = timestamp + _mintDelay + _mintTTL;

        vm.warp(deadline_ + 1);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.ExpiredMintProposal.selector, deadline_));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint_xxx() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, 95e18, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay + 1);

        vm.expectRevert(abi.encodeWithSelector(IProtocol.Undercollateralized.selector, 95e18, 90e18));

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mintM_undercollateralizedMint_outdatedCollateral() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp - _updateCollateralInterval);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, 95e18, block.timestamp, _alice);

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

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, _alice);

        vm.expectRevert(IProtocol.InvalidMintProposal.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId - 1);
    }

    function test_cancelMint_byValidator() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, _alice);

        vm.expectEmit();
        emit MintCanceled(mintId, _validator1);

        vm.prank(_validator1);
        _protocol.cancelMint(_minter1, mintId);

        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp, 0);
    }

    function test_cancelMint_notApprovedValidator() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, _alice);

        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(_alice);
        _protocol.cancelMint(_minter1, mintId);

        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp_) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, mintId);
        assertEq(destination_, _alice);
        assertEq(amount_, 100);
        assertEq(timestamp_, block.timestamp);
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
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 frozenUntil = block.timestamp + _minterFreezeTime;

        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);

        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        assertEq(_protocol.unfrozenTimeOf(_minter1), frozenUntil);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.proposeMint(amount, _alice);

        // fast-forward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        uint256 expectedMintId = _protocol.getMintId(_minter1, amount, _alice, _protocol.mintNonce() + 1);

        vm.expectEmit();
        emit MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint mintId = _protocol.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);
    }

    function test_freezeMinter_sequence() external {
        uint256 timestamp = block.timestamp;
        uint256 frozenUntil = timestamp + _minterFreezeTime;

        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);

        // first freezeMinter
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        vm.warp(timestamp + _minterFreezeTime / 2);

        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);

        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);
    }

    function test_freezeMinter_notApprovedValidator() external {
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(_alice);
        _protocol.freezeMinter(_minter1);
    }

    function test_freezeMinter_InactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);

        vm.expectRevert(IProtocol.InactiveMinter.selector);

        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);
    }

    function test_burnM() external {
        uint256 mintAmount = 1000000e18;

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, 10000000e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, block.timestamp, _alice);

        vm.warp(block.timestamp + _mintDelay);

        vm.expectEmit();
        emit MintExecuted(mintId);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        // 1 wei precision difference for the benefit of user
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);

        assertEq(_protocol.activeOwedMOf(_minter1), 1); // 1 wei leftover
        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 1); // 1 wei leftover

        // TODO: Check that burn was called.
    }

    function test_burnM_repayHalfOfOutstandingValue() external {
        _protocol.setCollateralOf(_minter1, 1000e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);

        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM / 2, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM / 2);

        assertEq(_protocol.activeOwedMOf(_minter1), activeOwedM / 2);

        // TODO: check that burn has been called.

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM / 2, _bob);

        vm.prank(_bob);
        _protocol.burnM(_minter1, activeOwedM / 2);

        assertEq(_protocol.activeOwedMOf(_minter1), 0);

        // TODO: check that burn has been called.
    }

    function test_burnM_notEnoughBalanceToRepay() external {
        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_updateCollateral_imposePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
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
        emit PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.activeOwedMOf(_minter1), activeOwedM + penalty);
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
        uint256 expectedPenalty = ((activeOwedM - maxAllowedOwedM) * _penaltyRate) / ONE;

        vm.expectEmit();
        emit PenaltyImposed(_minter1, expectedPenalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        // 1 wei precision loss
        assertEq(_protocol.activeOwedMOf(_minter1) + 1 wei, activeOwedM + expectedPenalty);
    }

    function test_updateCollateral_accrueBothPenalties() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(block.timestamp + 2 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
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
        emit PenaltyImposed(_minter1, penalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(newCollateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 expectedPenalty = (((activeOwedM + penalty) - (newCollateral * _mintRatio) / ONE) * _penaltyRate) / ONE;

        // precision loss of 2 wei-s - 1 per each penalty
        assertEq(_protocol.activeOwedMOf(_minter1) + 2 wei, activeOwedM + penalty + expectedPenalty);

        assertEq(_protocol.lastUpdateOf(_minter1), signatureTimestamp);
        assertEq(_protocol.lastUpdateIntervalOf(_minter1), _updateCollateralInterval);
        assertEq(_protocol.penalizedUntilOf(_minter1), signatureTimestamp);
    }

    function test_burnM_imposePenaltyForExpiredCollateralValue() external {
        _protocol.setCollateralOf(_minter1, 100e18);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(block.timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        assertEq(penalty, (activeOwedM * 3 * _penaltyRate) / ONE);

        vm.expectEmit();
        emit PenaltyImposed(_minter1, penalty);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);

        activeOwedM = _protocol.activeOwedMOf(_minter1);

        assertEq(activeOwedM, penalty);
    }

    function test_imposePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

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

        assertEq(_protocol.lastUpdateOf(_minter1), signatureTimestamp);
        assertEq(penalizedUntil, timestamp + _updateCollateralInterval);

        vm.prank(_alice);
        _protocol.burnM(_minter1, 10e18);

        assertEq(_protocol.lastUpdateOf(_minter1), signatureTimestamp);
        assertEq(_protocol.penalizedUntilOf(_minter1), penalizedUntil);
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervals() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);
    }

    function test_getPenaltyForMissedCollateralUpdates_noMissedIntervalsDespiteReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

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
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penaltyRate) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_oneMissedIntervalDespiteReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

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
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

        vm.warp(timestamp + (3 * _updateCollateralInterval) + 10);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, (3 * (_protocol.activeOwedMOf(_minter1) * _penaltyRate)) / ONE);
    }

    function test_getPenaltyForMissedCollateralUpdates_moreMissedIntervalDueToReducedInterval() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

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
        _protocol.setLastCollateralUpdateOf(_minter1, timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, 60e18);

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
        _protocol.setActiveMinter(_minter1, false);
        assertEq(_protocol.isActiveMinter(_minter1), false);

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit MinterActivated(_minter1, address(this));

        _protocol.activateMinter(_minter1);

        assertEq(_protocol.isActiveMinter(_minter1), true);
    }

    function test_deactivateMinter() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _protocol.deactivateMinter(_minter1);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_protocol.activeOwedMOf(_minter1), 0);
        assertEq(_protocol.inactiveOwedMOf(_minter1), activeOwedM);

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM, _alice);

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_deactivateMinter_imposePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp - _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM + penalty, _alice);

        vm.prank(_alice);
        _protocol.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_stillApprovedMinter() external {
        vm.expectRevert(IProtocol.StillApprovedMinter.selector);
        _protocol.deactivateMinter(_minter1);
    }

    function test_deactivateMinter_InactiveMinter() external {
        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        _protocol.deactivateMinter(_minter1);

        vm.expectRevert(IProtocol.InactiveMinter.selector);
        _protocol.deactivateMinter(_minter1);
    }

    function test_proposeRetrieval_xxx() external {
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(uint256(2))
        );

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 signatureTimestamp1 = block.timestamp;
        uint256 signatureTimestamp2 = signatureTimestamp1 - 10;

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
        emit CollateralUpdated(_minter1, collateral, retrievalIds, bytes32(0), signatureTimestamp2);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        uint256 expectedRetrievalId = _protocol.getRetrievalId(_minter1, collateral, _protocol.retrievalNonce() + 1);

        vm.expectEmit();
        emit RetrievalCreated(expectedRetrievalId, _minter1, collateral);

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(collateral);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), collateral);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), collateral);

        vm.warp(block.timestamp + 200);

        signatureTimestamp1 = block.timestamp - 100;
        signatureTimestamp2 = block.timestamp - 50;

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

        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), 0);
    }

    function test_proposeRetrieval_InactiveMinter() external {
        _protocol.setActiveMinter(_minter1, false);

        vm.expectRevert(IProtocol.InactiveMinter.selector);

        vm.prank(_alice);
        _protocol.proposeRetrieval(100);
    }

    function test_proposeRetrieval_notEnoughCollateral() external {
        uint256 collateral = 100e18;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, (collateral * _mintRatio) / ONE);

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

    function test_proposeRetrieval_multipleProposals() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral);
        _protocol.setLastCollateralUpdateOf(_minter1, block.timestamp);
        _protocol.setLastUpdateIntervalOf(_minter1, _updateCollateralInterval);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

        uint256 retrievalAmount = 10e18;
        uint256 expectedRetrievalId = _protocol.getRetrievalId(
            _minter1,
            retrievalAmount,
            _protocol.retrievalNonce() + 1
        );

        // First retrieval proposal
        vm.expectEmit();
        emit RetrievalCreated(expectedRetrievalId, _minter1, retrievalAmount);

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(retrievalAmount);

        assertEq(retrievalId, expectedRetrievalId);
        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), retrievalAmount);

        // Second retrieval proposal
        vm.prank(_minter1);
        uint256 newRetrievalId = _protocol.proposeRetrieval(retrievalAmount);

        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount * 2);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, newRetrievalId), retrievalAmount);

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

        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), retrievalAmount);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, newRetrievalId), 0);

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

        assertEq(_protocol.totalPendingCollateralRetrievalOf(_minter1), 0);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), 0);
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
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(uint256(0))
        );

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        assertEq(_protocol.collateralOf(_minter1), 100);
        assertEq(_protocol.lastUpdateOf(_minter1), block.timestamp);
    }

    function test_updateCollateral_someSignaturesAreInvalid() external {
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(uint256(1))
        );

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
        assertEq(_protocol.lastUpdateOf(_minter1), block.timestamp);
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
