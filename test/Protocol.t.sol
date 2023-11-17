// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { MockSPOGRegistrar, MockRateModel, MockMToken } from "./utils/Mocks.sol";
import { DigestHelper } from "./utils/DigestHelper.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

contract ProtocolTests is Test {
    uint256 internal constant ONE = 10000;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _spogVault = makeAddr("spogVault");

    address internal _minter1;
    uint256 internal _minter1Pk;

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

    MockSPOGRegistrar internal _spogRegistrar;
    MockMToken internal _mToken;
    ProtocolHarness internal _protocol;
    MockRateModel internal _minterRateModel;

    event CollateralUpdated(
        address indexed minter,
        uint256 collateral,
        uint256[] indexed retrieveIds,
        bytes32 indexed metadata,
        uint256 timestamp
    );

    event MintProposed(uint256 indexed mintId, address indexed minter, uint256 amount, address indexed destination);
    event MintExecuted(uint256 indexed mintId);
    event MintCanceled(uint256 indexed mintId, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);
    event MinterDeactivated(address indexed minter, uint256 owedM);

    event BurnExecuted(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyImposed(address indexed minter, uint256 amount);

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator1");

        _mToken = new MockMToken();

        _minterRateModel = new MockRateModel();
        _minterRateModel.setRate(_minterRate);

        _spogRegistrar = new MockSPOGRegistrar();

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validator1);

        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(_updateCollateralThreshold)
        );
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, bytes32(_updateCollateralInterval));

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, bytes32(_minterFreezeTime));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, bytes32(_mintDelay));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_TTL, bytes32(_mintTTL));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, bytes32(_mintRatio));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, _toBytes32(address(_minterRateModel)));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.PENALTY_RATE, bytes32(_penaltyRate));

        _spogRegistrar.setVault(_spogVault);

        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));
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
        signatures[0] = _getSignature(
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

        (uint256 collateral_, uint256 lastUpdated_, ) = _protocol.collateralOf(_minter1);

        assertEq(collateral_, collateral);
        assertEq(lastUpdated_, signatureTimestamp);
    }

    function test_updateCollateral_notApprovedMinter() external {
        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
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
        signatures[0] = _getSignature(_minter1, 100, retrievalIds, bytes32(0), block.timestamp, _validator1Pk);

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);

        (, uint256 lastUpdated_, ) = _protocol.collateralOf(_minter1);

        uint256 timestamp = lastUpdated_ - 1;

        timestamps[0] = timestamp;
        signatures[0] = _getSignature(_minter1, 100, retrievalIds, bytes32(0), timestamp, _validator1Pk);

        vm.expectRevert(IProtocol.StaleCollateralUpdate.selector);

        vm.prank(_minter1);
        _protocol.updateCollateral(100, retrievalIds, bytes32(0), validators, timestamps, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(uint256(3))
        );

        uint256 collateral = 100;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 timestamp = block.timestamp;

        bytes memory signature1_ = _getSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            timestamp,
            _validator1Pk
        );
        bytes memory signature2_ = _getSignature(
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
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, _alice, timestamp)));

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
        assertEq(timestamp_, timestamp);
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_notApprovedMinter() external {
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        vm.prank(_alice);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_proposeMint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        vm.warp(timestamp + _mintDelay);

        vm.expectRevert(IProtocol.Undercollateralized.selector);

        vm.prank(_minter1);
        _protocol.proposeMint(100e18, _alice);
    }

    function test_mint() external {
        uint256 collateral = 100e18;
        uint256 amount = 80e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

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

    function test_mint_outstandingValue() external {
        uint256 collateralAmount = 10000e18;
        uint256 mintAmount = 1000000e6;
        uint256 timestamp = block.timestamp;

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        uint256 initialActiveOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 initialIndex = _protocol.latestIndex();
        uint256 principalOfActiveOwedM = _protocol.principalOfActiveOwedMOf(_minter1);

        assertEq(initialActiveOwedM + 1, mintAmount);

        vm.warp(timestamp + _mintDelay + 1);

        uint256 indexAfter1Second = ContinuousIndexingMath.multiply(
            ContinuousIndexingMath.getContinuousIndex(ContinuousIndexingMath.convertFromBasisPoints(_minterRate), 1),
            initialIndex
        );

        uint256 expectedResult = ContinuousIndexingMath.multiply(principalOfActiveOwedM, indexAfter1Second);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult);

        vm.warp(timestamp + _mintDelay + 31_536_000);

        uint256 indexAfter1Year = ContinuousIndexingMath.multiply(
            ContinuousIndexingMath.getContinuousIndex(
                ContinuousIndexingMath.convertFromBasisPoints(_minterRate),
                31_536_000
            ),
            initialIndex
        );

        expectedResult = ContinuousIndexingMath.multiply(principalOfActiveOwedM, indexAfter1Year);

        assertEq(_protocol.activeOwedMOf(_minter1), expectedResult);
    }

    function test_mint_notApprovedMinter() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, _alice);

        vm.expectRevert(IProtocol.NotApprovedMinter.selector);

        vm.prank(_bob);
        _protocol.mintM(mintId);
    }

    function test_mint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, _minter1);

        vm.expectRevert(IProtocol.FrozenMinter.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mint_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, _alice);

        vm.warp(timestamp + _mintDelay / 2);

        vm.expectRevert(IProtocol.PendingMintProposal.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mint_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, _alice);

        vm.warp(timestamp + _mintDelay + _mintTTL + 1);

        vm.expectRevert(IProtocol.ExpiredMintProposal.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay + 1);

        vm.expectRevert(IProtocol.Undercollateralized.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mint_undercollateralizedMint_outdatedCollateral() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp - _updateCollateralInterval);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay + 1);

        vm.expectRevert(IProtocol.Undercollateralized.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId);
    }

    function test_mint_invalidMintRequest() external {
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_minter1);
        _protocol.mintM(1);
    }

    function test_mint_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, _alice);

        vm.expectRevert(IProtocol.InvalidMintProposal.selector);

        vm.prank(_minter1);
        _protocol.mintM(mintId - 1);
    }

    function test_cancel_byValidator() external {
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

    function test_cancel_byMinter() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, _alice);

        vm.expectEmit();
        emit MintCanceled(mintId, _minter1);

        vm.prank(_minter1);
        _protocol.cancelMint(mintId);

        (uint256 mintId_, address destination_, uint256 amount_, uint256 timestamp) = _protocol.mintProposalOf(
            _minter1
        );

        assertEq(mintId_, 0);
        assertEq(destination_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp, 0);
    }

    function test_cancel_notApprovedValidator() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, _alice);

        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(_alice);
        _protocol.cancelMint(_minter1, mintId);
    }

    function test_cancel_invalidMintRequest() external {
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_minter1);
        _protocol.cancelMint(1);

        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        vm.prank(_validator1);
        _protocol.cancelMint(_minter1, 1);
    }

    function test_freeze() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, collateral, block.timestamp);

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

        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, _alice, block.timestamp)));

        vm.expectEmit();
        emit MintProposed(expectedMintId, _minter1, amount, _alice);

        vm.prank(_minter1);
        uint mintId = _protocol.proposeMint(amount, _alice);

        assertEq(mintId, expectedMintId);
    }

    function test_freeze_sequence() external {
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

    function test_freeze_notApprovedValidator() external {
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        vm.prank(_alice);
        _protocol.freezeMinter(_minter1);
    }

    function test_burn() external {
        uint256 collateralAmount = 10000000e18;
        uint256 mintAmount = 1000000e18;
        uint256 timestamp = block.timestamp;

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, timestamp, _alice);

        vm.warp(timestamp + _mintDelay);

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
    }

    function test_burn_repayHalfOfOutstandingValue() external {
        _protocol.setCollateralOf(_minter1, 1000e18, block.timestamp);

        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);
        _protocol.setIndex(1e18);

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

    function test_burn_notEnoughBalanceToRepay() external {
        uint256 principalOfActiveOwedM = 100e18;

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, principalOfActiveOwedM);
        _protocol.setIndex(1e18);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();

        vm.prank(_alice);
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_updateCollateral_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, collateral, block.timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

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
        signatures[0] = _getSignature(
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

    function test_updateCollateral_accruePenaltyForMissedCollateralUpdates() external {
        uint256 collateral = 100e18;
        uint256 amount = 180e18;

        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        uint256 signatureTimestamp = block.timestamp;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getSignature(
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

        signatures[0] = _getSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 maxOwedM = (collateral * _mintRatio) / ONE;
        uint256 expectedPenalty = ((activeOwedM - maxOwedM) * _penaltyRate) / ONE;

        vm.expectEmit();
        emit PenaltyImposed(_minter1, expectedPenalty);

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        // 1 wei precision loss
        assertEq(_protocol.activeOwedMOf(_minter1) + 1 wei, activeOwedM + expectedPenalty);
    }

    function test_updateCollateral_accrueBothPenalties() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, collateral, block.timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

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
        signatures[0] = _getSignature(
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

        (, uint256 lastUpdated_, uint256 penalizedUntil_) = _protocol.collateralOf(_minter1);

        assertEq(lastUpdated_, signatureTimestamp);
        assertEq(penalizedUntil_, signatureTimestamp);
    }

    function test_burn_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;

        _protocol.setCollateralOf(_minter1, collateral, block.timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

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

    function test_accruePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

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
        signatures[0] = _getSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validator1Pk
        );

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        (, uint256 lastUpdated, uint256 penalizedUntil) = _protocol.collateralOf(_minter1);

        assertEq(lastUpdated, signatureTimestamp);
        assertEq(penalizedUntil, timestamp + _updateCollateralInterval);

        vm.prank(_alice);
        _protocol.burnM(_minter1, 10e18);

        (, uint256 lastUpdated_, uint256 penalizedUntil_) = _protocol.collateralOf(_minter1);

        assertEq(lastUpdated_, lastUpdated);
        assertEq(penalizedUntil, penalizedUntil_ - 10);
    }

    function test_remove() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2, block.timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM);

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

    function test_remove_accruePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2, block.timestamp - _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM + penalty);

        vm.prank(_alice);
        _protocol.deactivateMinter(_minter1);
    }

    function test_remove_stillApprovedMinter() external {
        vm.expectRevert(IProtocol.StillApprovedMinter.selector);
        _protocol.deactivateMinter(_minter1);
    }

    function test_retrieve() external {
        uint256 collateral = 100;
        uint256 signatureTimestamp1 = block.timestamp;
        uint256 signatureTimestamp2 = signatureTimestamp1 - 10;
        uint256[] memory retrievalIds = new uint256[](0);

        address[] memory validators = new address[](2);
        validators[1] = _validator1;
        validators[0] = _validator2;

        uint256[] memory timestamps = new uint256[](2);
        timestamps[1] = signatureTimestamp1;
        timestamps[0] = signatureTimestamp2;

        bytes[] memory signatures = new bytes[](2);
        signatures[1] = _getSignature(
            _minter1,
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp1,
            _validator1Pk
        );
        signatures[0] = _getSignature(
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

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(100);

        assertEq(_protocol.totalCollateralPendingRetrievalOf(_minter1), 100);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), 100);
    }

    function test_retrieve_notApprovedMinter() external {
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        vm.prank(_alice);
        _protocol.proposeRetrieval(100);
    }

    function test_retrieve_notEnoughCollateral() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, (collateral * _mintRatio) / ONE);

        vm.expectRevert(IProtocol.Undercollateralized.selector);
        vm.prank(_minter1);
        _protocol.proposeRetrieval(10e18);
    }

    function _getSignature(
        address minter,
        uint256 collateral,
        uint256[] memory retrievalIds,
        bytes32 metadata,
        uint256 timestamp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = DigestHelper.getUpdateCollateralDigest(
            address(_protocol),
            minter,
            collateral,
            retrievalIds,
            metadata,
            timestamp
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function _toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
