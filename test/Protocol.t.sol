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
    uint256 internal _penalty = 100; // 1%, bps

    MockSPOGRegistrar internal _spogRegistrar;
    MockMToken internal _mToken;
    ProtocolHarness internal _protocol;
    MockRateModel internal _minterRateModel;

    event CollateralUpdated(address indexed minter, uint256 collateral, bytes32 indexed metadata, uint256 timestamp);

    event MintProposed(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintCanceled(uint256 mintId, address indexed minter, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);
    event MinterDeactivated(address indexed minter, uint256 owedM, address indexed caller);

    event BurnExecuted(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyImposed(address indexed minter, uint256 amount, address indexed caller);

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
        _spogRegistrar.updateConfig(SPOGRegistrarReader.PENALTY, bytes32(_penalty));

        _spogRegistrar.setVault(_spogVault);

        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));
    }

    function test_updateCollateral() external {
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;
        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, collateral, "", retrievalIds, timestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = timestamp;

        vm.prank(_minter1);
        vm.expectEmit();
        emit CollateralUpdated(_minter1, collateral, "", timestamp);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        (uint256 collateral_, uint256 lastUpdated_, ) = _protocol.collateralOf(_minter1);
        assertEq(collateral_, collateral);
        assertEq(lastUpdated_, timestamp);
    }

    function test_updateCollateral_notApprovedMinter() external {
        address[] memory validators = new address[](0);
        bytes[] memory signatures = new bytes[](0);
        uint256[] memory retrievalIds = new uint256[](0);
        uint256[] memory timestamps = new uint256[](0);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.updateCollateral(100e18, "", retrievalIds, validators, timestamps, signatures);
    }

    function test_updateCollateral_signatureArrayLengthsMismatch() external {
        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = _validator1;

        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, 100, "", retrievalIds, block.timestamp, _validator1Pk);

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature;
        signatures[1] = signature;
        signatures[2] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.SignatureArrayLengthsMismatch.selector);
        _protocol.updateCollateral(100, "", retrievalIds, validators, timestamps, signatures);

        validators[2] = _validator1;
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.SignatureArrayLengthsMismatch.selector);
        _protocol.updateCollateral(100, "", retrievalIds, validators, timestamps, signatures);
    }

    // function test_updateCollateral_expiredCollateralUpdate() external {
    //     uint256 timestamp = block.timestamp - _updateCollateralInterval - 1;
    //     uint256[] memory retrievalIds = new uint256[](0);
    //     bytes memory signature = _getSignature(_minter1, 100, "", retrievalIds, timestamp, _validator1Pk);

    //     address[] memory validators = new address[](1);
    //     validators[0] = _validator1;

    //     bytes[] memory signatures = new bytes[](1);
    //     signatures[0] = signature;

    //     uint256[] memory timestamps = new uint256[](1);
    //     timestamps[0] = timestamp;

    //     vm.prank(_minter1);
    //     vm.expectRevert(IProtocol.ExpiredCollateralUpdate.selector);
    //     _protocol.updateCollateral(100, "", retrievalIds, validators, timestamps, signatures);
    // }

    function test_updateCollateral_staleCollateralUpdate() external {
        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, 100, "", retrievalIds, block.timestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;

        vm.prank(_minter1);
        _protocol.updateCollateral(100, "", retrievalIds, validators, timestamps, signatures);

        (, uint256 lastUpdated_, ) = _protocol.collateralOf(_minter1);

        uint256 timestamp = lastUpdated_ - 1;
        signature = _getSignature(_minter1, 100, "", retrievalIds, timestamp, _validator1Pk);
        signatures[0] = signature;
        timestamps[0] = timestamp;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.StaleCollateralUpdate.selector);
        _protocol.updateCollateral(100, "", retrievalIds, validators, timestamps, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD,
            bytes32(uint256(3))
        );
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;

        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature1_ = _getSignature(_minter1, collateral, "", retrievalIds, timestamp, _validator1Pk);
        bytes memory signature2_ = _getSignature(_minter1, collateral, "", retrievalIds, timestamp, _validator2Pk);

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

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidSignatureOrder.selector);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);
    }

    function test_proposeMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address destination_ = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        vm.pauseGasMetering();
        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, destination_, timestamp, gasleft())));

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintProposed(expectedMintId, _minter1, amount, destination_);
        uint256 mintId = _protocol.proposeMint(amount, destination_);
        assertEq(mintId, expectedMintId);

        vm.resumeGasMetering();

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintProposalOf(_minter1);
        assertEq(mintId_, mintId);
        assertEq(amount_, amount);
        assertEq(to_, destination_);
        assertEq(timestamp_, timestamp);
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_notApprovedMinter() external {
        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.proposeMint(100e18, makeAddr("to"));
    }

    function test_proposeMint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.Undercollateralized.selector);
        // mint ratio * collateral is not satisfied
        _protocol.proposeMint(100e18, destination);
    }

    function test_mint() external {
        uint256 collateral = 100e18;
        uint256 amount = 80e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, destination, 1);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintExecuted(mintId, _minter1, amount, destination);
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
        address to = makeAddr("to");

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, timestamp, to, 1);

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
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, makeAddr("alice"), 1);

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freezeMinter(_minter1);

        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100e18, block.timestamp, _minter1, 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, makeAddr("alice"), 1);

        vm.warp(timestamp + _mintDelay / 2);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.PendingMintProposal.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, timestamp, makeAddr("alice"), 1);

        vm.warp(timestamp + _mintDelay + _mintTTL + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.ExpiredMintProposal.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, destination, 1);

        vm.warp(timestamp + _mintDelay + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.Undercollateralized.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_undercollateralizedMint_outdatedCollateral() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp - _updateCollateralInterval);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, destination, 1);

        vm.warp(timestamp + _mintDelay + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.Undercollateralized.selector);
        _protocol.mintM(mintId);
    }

    function test_mint_invalidMintRequest() external {
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        _protocol.mintM(1);
    }

    function test_mint_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");
        uint256 gasLeft = 1;

        uint256 mintId = _protocol.setMintProposalOf(_minter1, amount, timestamp, destination, gasLeft);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        _protocol.mintM(mintId - 1);
    }

    function test_cancel_byValidator() external {
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, makeAddr("alice"), 1);

        vm.prank(_validator1);
        vm.expectEmit();
        emit MintCanceled(mintId, _minter1, _validator1);
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
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, makeAddr("alice"), 1);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintCanceled(mintId, _minter1, _minter1);
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
        uint256 mintId = _protocol.setMintProposalOf(_minter1, 100, block.timestamp, makeAddr("alice"), 1);

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.cancelMint(_minter1, mintId);
    }

    function test_cancel_invalidMintRequest() external {
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        _protocol.cancelMint(1);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.InvalidMintProposal.selector);
        _protocol.cancelMint(_minter1, 1);
    }

    function test_freeze() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        uint256 frozenUntil = timestamp + _minterFreezeTime;

        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);
        _protocol.freezeMinter(_minter1);

        assertEq(_protocol.unfrozenTimeOf(_minter1), frozenUntil);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.proposeMint(amount, destination);

        // fast-worward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        vm.pauseGasMetering();
        uint256 expectedMintId = uint256(
            keccak256(abi.encode(_minter1, amount, destination, block.timestamp, gasleft()))
        );

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintProposed(expectedMintId, _minter1, amount, destination);
        uint mintId = _protocol.proposeMint(amount, destination);

        vm.resumeGasMetering();

        assertEq(mintId, expectedMintId);
    }

    function test_freeze_sequence() external {
        uint256 timestamp = block.timestamp;

        uint256 frozenUntil = timestamp + _minterFreezeTime;

        // first freezeMinter
        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);
        _protocol.freezeMinter(_minter1);

        uint256 newFreezeTimestamp = timestamp + _minterFreezeTime / 2;
        vm.warp(newFreezeTimestamp);

        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);
        _protocol.freezeMinter(_minter1);
    }

    function test_freeze_notApprovedValidator() external {
        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.freezeMinter(_minter1);
    }

    function test_xxx_burn() external {
        uint256 collateralAmount = 10000000e18;
        uint256 mintAmount = 1000000e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintProposalOf(_minter1, mintAmount, timestamp, destination, 1);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mintM(mintId);

        // 1 wei precision difference for the benefit of user
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);

        vm.prank(destination);
        emit BurnExecuted(_minter1, activeOwedM, destination);
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

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM / 2, alice);

        vm.prank(alice);
        _protocol.burnM(_minter1, activeOwedM / 2);

        assertEq(_protocol.activeOwedMOf(_minter1), activeOwedM / 2);

        // TODO: check that burn has been called.

        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM / 2, bob);

        vm.prank(bob);
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
        vm.prank(makeAddr("alice"));
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_updateCollateral_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

        vm.warp(timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 3 * _penalty) / ONE);

        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, collateral, "", retrievalIds, block.timestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;

        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyImposed(_minter1, penalty, _minter1);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        assertEq(_protocol.activeOwedMOf(_minter1), activeOwedM + penalty);
    }

    function test_updateCollateral_accruePenaltyForMissedCollateralUpdates() external {
        uint256 collateral = 100e18;
        uint256 amount = 180e18;
        uint256 timestamp = block.timestamp;

        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, collateral, "", retrievalIds, timestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = timestamp;

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

        vm.warp(timestamp + _updateCollateralInterval - 1);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        assertEq(penalty, 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signature = _getSignature(_minter1, collateral, "", retrievalIds, block.timestamp, _validator1Pk);
        signatures[0] = signature;
        timestamps[0] = block.timestamp;

        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 maxOwedM = (collateral * _mintRatio) / ONE;
        uint256 expectedPenalty = ((activeOwedM - maxOwedM) * _penalty) / ONE;
        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyImposed(_minter1, expectedPenalty, _minter1);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        // 1 wei precision loss
        assertEq(_protocol.activeOwedMOf(_minter1) + 1 wei, activeOwedM + expectedPenalty);
    }

    function test_updateCollateral_accrueBothPenalties() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

        vm.warp(timestamp + 2 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 2 * _penalty) / ONE);

        uint256 newCollateral = 10e18;
        uint256 newTimestamp = block.timestamp;

        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature = _getSignature(_minter1, newCollateral, "", retrievalIds, newTimestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = newTimestamp;

        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyImposed(_minter1, penalty, _minter1);
        _protocol.updateCollateral(newCollateral, "", retrievalIds, validators, timestamps, signatures);

        uint256 expectedPenalty = (((activeOwedM + penalty) - (newCollateral * _mintRatio) / ONE) * _penalty) / ONE;

        // precision loss of 2 wei-s - 1 per each penalty
        assertEq(_protocol.activeOwedMOf(_minter1) + 2 wei, activeOwedM + penalty + expectedPenalty);

        (, uint256 lastUpdated_, uint256 penalizedUntil_) = _protocol.collateralOf(_minter1);

        assertEq(lastUpdated_, newTimestamp);
        assertEq(penalizedUntil_, newTimestamp);
    }

    function test_burn_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address destination = makeAddr("alice");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, amount);

        vm.warp(timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        assertEq(penalty, (activeOwedM * 3 * _penalty) / ONE);

        _mintTo(destination, activeOwedM);

        vm.prank(destination);
        vm.expectEmit();
        emit PenaltyImposed(_minter1, penalty, destination);
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
        assertEq(penalty, (_protocol.activeOwedMOf(_minter1) * _penalty) / ONE);

        uint256[] memory retrievalIds = new uint256[](1);
        bytes memory signature = _getSignature(_minter1, collateral, "", retrievalIds, block.timestamp, _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = block.timestamp;

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        (, uint256 lastUpdated, uint256 penalizedUntil) = _protocol.collateralOf(_minter1);
        assertEq(lastUpdated, block.timestamp);
        assertEq(penalizedUntil, timestamp + _updateCollateralInterval);

        address alice = makeAddr("alice");
        _mintTo(alice, 10e18);

        vm.prank(alice);
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

        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM, alice);
        _protocol.deactivateMinter(_minter1);

        assertEq(_protocol.principalOfActiveOwedMOf(_minter1), 0);
        assertEq(_protocol.activeOwedMOf(_minter1), 0);
        assertEq(_protocol.inactiveOwedMOf(_minter1), activeOwedM);

        _mintTo(alice, activeOwedM);

        vm.prank(alice);
        vm.expectEmit();
        emit BurnExecuted(_minter1, activeOwedM, alice);
        _protocol.burnM(_minter1, activeOwedM);
    }

    function test_remove_accruePenaltyForExpiredCollateralValue() external {
        uint256 mintAmount = 1000000e18;

        _protocol.setCollateralOf(_minter1, mintAmount * 2, block.timestamp - _updateCollateralInterval);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, mintAmount);
        uint256 activeOwedM = _protocol.activeOwedMOf(_minter1);
        uint256 penalty = _protocol.getPenaltyForMissedCollateralUpdates(_minter1);

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minter1);

        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectEmit();
        emit MinterDeactivated(_minter1, activeOwedM + penalty, alice);
        _protocol.deactivateMinter(_minter1);
    }

    function test_remove_stillApprovedMinter() external {
        vm.expectRevert(IProtocol.StillApprovedMinter.selector);
        _protocol.deactivateMinter(_minter1);
    }

    function test_retrieve() external {
        uint256 collateral = 100;
        uint256 timestamp1 = block.timestamp;
        uint256 timestamp2 = timestamp1 - 10;
        uint256[] memory retrievalIds = new uint256[](0);
        bytes memory signature1_ = _getSignature(_minter1, collateral, "", retrievalIds, timestamp1, _validator1Pk);
        bytes memory signature2_ = _getSignature(_minter1, collateral, "", retrievalIds, timestamp2, _validator2Pk);

        address[] memory validators = new address[](2);
        validators[1] = _validator1;
        validators[0] = _validator2;

        bytes[] memory signatures = new bytes[](2);
        signatures[1] = signature1_;
        signatures[0] = signature2_;

        uint256[] memory timestamps = new uint256[](2);
        timestamps[1] = timestamp1;
        timestamps[0] = timestamp2;

        vm.prank(_minter1);
        vm.expectEmit();
        emit CollateralUpdated(_minter1, collateral, "", timestamp2);
        _protocol.updateCollateral(collateral, "", retrievalIds, validators, timestamps, signatures);

        vm.prank(_minter1);
        uint256 retrievalId = _protocol.proposeRetrieval(100);

        assertEq(_protocol.totalCollateralPendingRetrievalOf(_minter1), 100);
        assertEq(_protocol.pendingRetrievalsOf(_minter1, retrievalId), 100);
    }

    function test_retrieve_notApprovedMinter() external {
        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.proposeRetrieval(100);
    }

    function test_retrieve_notEnoughCollateral() external {
        uint256 collateral = 100e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setPrincipalOfActiveOwedMOf(_minter1, (collateral * _mintRatio) / ONE);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.Undercollateralized.selector);
        _protocol.proposeRetrieval(10e18);
    }

    function _mintTo(address account, uint256 amount) internal {
        vm.prank(address(_protocol));
        _mToken.mint(account, amount);
    }

    function _getSignature(
        address minter,
        uint256 collateral,
        bytes32 metadata,
        uint256[] memory retrievalIds,
        uint256 timestamp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = DigestHelper.getUpdateCollateralDigest(
            address(_protocol),
            minter,
            collateral,
            metadata,
            retrievalIds,
            timestamp
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _toBytes32(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }
}
