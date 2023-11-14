// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { InterestMath } from "../src/libs/InterestMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { MockSPOGRegistrar, MockRateModel, MockMToken } from "./utils/Mocks.sol";
import { DigestHelper } from "./utils/DigestHelper.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

contract ProtocolTests is Test {
    uint256 internal constant ONE = 10000;

    address internal _minter1;
    uint256 internal _minter1Pk;

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralQuorum = 1;
    uint256 internal _updateCollateralInterval = 2000;
    uint256 internal _minterFreezeTime = 1000;
    uint256 internal _mintDelay = 1000;
    uint256 internal _mintTTL = 500;
    uint256 internal _mRate = 400; // 4%, bps
    uint256 internal _mintRatio = 9000; // 90%, bps
    uint256 internal _penalty = 100; // 1%, bps

    MockSPOGRegistrar internal _spogRegistrar;
    MockMToken internal _mToken;
    ProtocolHarness internal _protocol;
    MockRateModel internal _mRateModel;

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    event MintRequestedCreated(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(uint256 mintId, address indexed minter, address indexed canceller);

    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event Burn(address indexed minter, uint256 amount, address indexed payer);

    event PenaltyAccrued(address indexed minter, uint256 amount, address indexed caller);

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator1");

        _spogRegistrar = new MockSPOGRegistrar();
        _mToken = new MockMToken();

        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minter1);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validator1);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM, bytes32(_updateCollateralQuorum));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, bytes32(_updateCollateralInterval));

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, bytes32(_minterFreezeTime));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, bytes32(_mintDelay));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_TTL, bytes32(_mintTTL));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, bytes32(_mintRatio));

        _mRateModel = new MockRateModel();
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, _toBytes32(address(_mRateModel)));
        _mRateModel.setRate(_mRate);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.PENALTY, bytes32(_penalty));
    }

    function test_updateCollateral() external {
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;
        bytes memory signature = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        vm.expectEmit();
        emit CollateralUpdated(_minter1, collateral, timestamp, "");
        _protocol.updateCollateral(collateral, block.timestamp, "", validators, signatures);

        (uint256 amount, uint256 lastUpdated, ) = _protocol.collateralOf(_minter1);
        assertEq(amount, collateral);
        assertEq(lastUpdated, timestamp);
    }

    function test_updateCollateral_notApprovedMinter() external {
        address[] memory validators = new address[](1);
        bytes[] memory signatures = new bytes[](1);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.updateCollateral(100, block.timestamp, "", validators, signatures);
    }

    function test_updateCollateral_invalidSignaturesLength() external {
        bytes memory signature = _getSignature(_minter1, 100, block.timestamp, "", _validator1Pk);

        address[] memory validators = new address[](2);
        validators[0] = _validator1;
        validators[1] = _validator1;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature;
        signatures[1] = signature;
        signatures[2] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidSignaturesLength.selector);
        _protocol.updateCollateral(100, block.timestamp, "", validators, signatures);
    }

    function test_updateCollateral_expiredTimestamp() external {
        uint256 timestamp = block.timestamp - _updateCollateralInterval - 1;
        bytes memory signature = _getSignature(_minter1, 100, timestamp, "", _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.ExpiredTimestamp.selector);
        _protocol.updateCollateral(100, timestamp, "", validators, signatures);
    }

    function test_updateCollateral_staleTimestamp() external {
        bytes memory signature = _getSignature(_minter1, 100, block.timestamp, "", _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        _protocol.updateCollateral(100, block.timestamp, "", validators, signatures);

        (, uint256 lastUpdated_, ) = _protocol.collateralOf(_minter1);

        uint256 timestamp = lastUpdated_ - 1;
        signature = _getSignature(_minter1, 100, timestamp, "", _validator1Pk);
        signatures[0] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.StaleTimestamp.selector);
        _protocol.updateCollateral(100, timestamp, "", validators, signatures);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM, bytes32(uint256(3)));
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;

        bytes memory signature1 = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);
        bytes memory signature2 = _getSignature(_minter1, collateral, timestamp, "", _validator2Pk);

        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = _validator2;
        validators[2] = _validator2;

        bytes[] memory signatures = new bytes[](3);
        signatures[0] = signature1;
        signatures[1] = signature2;
        signatures[2] = signature2;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.NotEnoughValidSignatures.selector);
        _protocol.updateCollateral(collateral, timestamp, "", validators, signatures);
    }

    function test_proposeMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        vm.pauseGasMetering();
        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, to, timestamp, gasleft())));

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestedCreated(expectedMintId, _minter1, amount, to);
        uint256 mintId = _protocol.proposeMint(amount, to);
        assertEq(mintId, expectedMintId);

        vm.resumeGasMetering();

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequestOf(_minter1);
        assertEq(mintId_, mintId);
        assertEq(amount_, amount);
        assertEq(to_, to);
        assertEq(timestamp_, timestamp);
    }

    function test_proposeMint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freeze(_minter1);

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
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.UndercollateralizedMint.selector);
        // mint ratio * collateral is not satisfied
        _protocol.proposeMint(100e18, to);
    }

    function test_mint() external {
        uint256 collateral = 100e18;
        uint256 amount = 80e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintRequestOf(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestExecuted(mintId, _minter1, amount, to);
        _protocol.mint(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequestOf(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertTrue(_protocol.normalizedPrincipalOf(_minter1) > 0);

        // TODO: check that mint has been called.
    }

    function test_mint_outstandingValue() external {
        uint256 collateralAmount = 10000e18;
        uint256 mintAmount = 1000000e6;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintRequestOf(_minter1, mintAmount, timestamp, to, 1);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mint(mintId);

        uint256 initialOutstandingValue = _protocol.outstandingValueOf(_minter1);
        uint256 initialIndex = _protocol.mIndex();
        uint256 minterNormalizedPrincipal = _protocol.normalizedPrincipalOf(_minter1);

        assertEq(initialOutstandingValue + 1, mintAmount);

        vm.warp(timestamp + _mintDelay + 1);

        uint256 indexAfter1Second = InterestMath.multiply(
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(_mRate), 1),
            initialIndex
        );

        uint256 expectedResult = InterestMath.multiply(minterNormalizedPrincipal, indexAfter1Second);
        assertEq(_protocol.outstandingValueOf(_minter1), expectedResult);

        vm.warp(timestamp + _mintDelay + 31_536_000);

        uint256 indexAfter1Year = InterestMath.multiply(
            InterestMath.getContinuousIndex(InterestMath.convertFromBasisPoints(_mRate), 31_536_000),
            initialIndex
        );

        expectedResult = InterestMath.multiply(minterNormalizedPrincipal, indexAfter1Year);
        assertEq(_protocol.outstandingValueOf(_minter1), expectedResult);
    }

    function test_mint_notApprovedMinter() external {
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100e18, block.timestamp, makeAddr("to"), 1);

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.mint(mintId);
    }

    function test_mint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freeze(_minter1);

        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100e18, block.timestamp, _minter1, 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.mint(mintId);
    }

    function test_mint_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100, timestamp, makeAddr("to"), 1);

        vm.warp(timestamp + _mintDelay / 2);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.PendingMintRequest.selector);
        _protocol.mint(mintId);
    }

    function test_mint_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100, timestamp, makeAddr("to"), 1);

        vm.warp(timestamp + _mintDelay + _mintTTL + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.ExpiredMintRequest.selector);
        _protocol.mint(mintId);
    }

    function test_mint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintRequestOf(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintDelay + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.UndercollateralizedMint.selector);
        _protocol.mint(mintId);
    }

    function test_mint_undercollateralizedMint_outdatedCollateral() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp - _updateCollateralInterval);
        uint256 mintId = _protocol.setMintRequestOf(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintDelay + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.UndercollateralizedMint.selector);
        _protocol.mint(mintId);
    }

    function test_mint_invalidMintRequest() external {
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.mint(1);
    }

    function test_mint_invalidMintRequest_mismatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");
        uint256 gasLeft = 1;

        uint256 mintId = _protocol.setMintRequestOf(_minter1, amount, timestamp, to, gasLeft);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.mint(mintId - 1);
    }

    function test_cancel_byValidator() external {
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100, block.timestamp, makeAddr("to"), 1);

        vm.prank(_validator1);
        vm.expectEmit();
        emit MintRequestCanceled(mintId, _minter1, _validator1);
        _protocol.cancel(_minter1, mintId);

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequestOf(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);
    }

    function test_cancel_byMinter() external {
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100, block.timestamp, makeAddr("to"), 1);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestCanceled(mintId, _minter1, _minter1);
        _protocol.cancel(mintId);

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequestOf(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);
    }

    function test_cancel_notApprovedValidator() external {
        uint256 mintId = _protocol.setMintRequestOf(_minter1, 100, block.timestamp, makeAddr("to"), 1);

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.cancel(_minter1, mintId);
    }

    function test_cancel_invalidMintRequest() external {
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.cancel(1);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.cancel(_minter1, 1);
    }

    function test_freeze() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);

        uint256 frozenUntil = timestamp + _minterFreezeTime;

        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);
        _protocol.freeze(_minter1);

        assertEq(_protocol.unfrozenTimeOf(_minter1), frozenUntil);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.proposeMint(amount, to);

        // fast-worward to the time when minter is unfrozen
        vm.warp(frozenUntil);

        vm.pauseGasMetering();
        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, to, block.timestamp, gasleft())));

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestedCreated(expectedMintId, _minter1, amount, to);
        uint mintId = _protocol.proposeMint(amount, to);

        vm.resumeGasMetering();

        assertEq(mintId, expectedMintId);
    }

    function test_freeze_sequence() external {
        uint256 timestamp = block.timestamp;

        uint256 frozenUntil = timestamp + _minterFreezeTime;

        // first freeze
        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);
        _protocol.freeze(_minter1);

        uint256 newFreezeTimestamp = timestamp + _minterFreezeTime / 2;
        vm.warp(newFreezeTimestamp);

        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil + _minterFreezeTime / 2);
        _protocol.freeze(_minter1);
    }

    function test_freeze_notApprovedValidator() external {
        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.freeze(_minter1);
    }

    function test_xxx_burn() external {
        uint256 collateralAmount = 10000000e18;
        uint256 mintAmount = 1000000e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        // initiate harness functions
        _protocol.setCollateralOf(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintRequestOf(_minter1, mintAmount, timestamp, to, 1);

        vm.warp(timestamp + _mintDelay);

        vm.prank(_minter1);
        _protocol.mint(mintId);

        vm.expectEmit();
        emit Burn(_minter1, mintAmount - 1 wei, to);

        vm.prank(to);
        _protocol.burn(_minter1, mintAmount);

        // minter repaid all its outstandingValue
        assertEq(_protocol.outstandingValueOf(_minter1), 0);
        // 1 wei is left in the user `to`
        assertEq(_protocol.normalizedPrincipalOf(_minter1), 0);
    }

    function test_burn_repayHalfOfOutstandingValue() external {
        _protocol.setCollateralOf(_minter1, 1000e18, block.timestamp);

        uint256 normalizedPrincipal = 100e18;
        _protocol.setNormalizedPrincipalOf(_minter1, normalizedPrincipal);
        _protocol.setMIndex(1e18);

        uint256 minterOutstandingValue = _protocol.outstandingValueOf(_minter1);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.expectEmit();
        emit Burn(_minter1, minterOutstandingValue / 2, alice);

        vm.prank(alice);
        _protocol.burn(_minter1, minterOutstandingValue / 2);

        assertEq(_protocol.outstandingValueOf(_minter1), minterOutstandingValue / 2);

        // TODO: check that burn has been called.

        vm.expectEmit();
        emit Burn(_minter1, minterOutstandingValue / 2, bob);

        vm.prank(bob);
        _protocol.burn(_minter1, minterOutstandingValue / 2);

        assertEq(_protocol.outstandingValueOf(_minter1), 0);

        // TODO: check that burn has been called.
    }

    function test_burn_notEnoughBalanceToRepay() external {
        uint256 normalizedPrincipal = 100e18;
        _protocol.setNormalizedPrincipalOf(_minter1, normalizedPrincipal);
        _protocol.setMIndex(1e18);

        uint256 minterOutstandingValue = _protocol.outstandingValueOf(_minter1);

        _mToken.setBurnFail(true);

        vm.expectRevert();
        vm.prank(makeAddr("alice"));
        _protocol.burn(_minter1, minterOutstandingValue);
    }

    function test_updateCollateral_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setNormalizedPrincipalOf(_minter1, amount);

        vm.warp(timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        uint256 minterOutstandingValue = _protocol.outstandingValueOf(_minter1);
        assertEq(penalty, (minterOutstandingValue * 3 * _penalty) / ONE);

        bytes memory signature = _getSignature(_minter1, collateral, block.timestamp, "", _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyAccrued(_minter1, penalty, _minter1);
        _protocol.updateCollateral(collateral, block.timestamp, "", validators, signatures);

        assertEq(_protocol.outstandingValueOf(_minter1), minterOutstandingValue + penalty);
    }

    function test_updateCollateral_accruePenaltyForExcessiveOustandingValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 180e18;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);

        address[] memory validators = new address[](1);
        validators[0] = _validator1;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, timestamp, "", validators, signatures);

        _protocol.setNormalizedPrincipalOf(_minter1, amount);

        vm.warp(timestamp + _updateCollateralInterval - 1);

        uint256 penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        assertEq(penalty, 0);

        // Step 2 - Update Collateral with excessive outstanding value
        signature = _getSignature(_minter1, collateral, block.timestamp, "", _validator1Pk);
        signatures[0] = signature;

        uint256 oustandingDebt = _protocol.outstandingValueOf(_minter1);
        uint256 allowedOutstandingDebt = (collateral * _mintRatio) / ONE;
        uint256 expectedPenalty = ((oustandingDebt - allowedOutstandingDebt) * _penalty) / ONE;
        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyAccrued(_minter1, expectedPenalty, _minter1);
        _protocol.updateCollateral(collateral, block.timestamp, "", validators, signatures);

        // 1 wei precision loss
        assertEq(_protocol.outstandingValueOf(_minter1) + 1 wei, oustandingDebt + expectedPenalty);
    }

    function test_updateCollateral_accrueBothPenalties() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setNormalizedPrincipalOf(_minter1, amount);

        vm.warp(timestamp + 2 * _updateCollateralInterval);

        uint256 penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        uint256 minterOutstandingValue = _protocol.outstandingValueOf(_minter1);
        assertEq(penalty, (minterOutstandingValue * 2 * _penalty) / ONE);

        uint256 newCollateral = 10e18;
        uint256 newTimestamp = block.timestamp;
        bytes memory signature = _getSignature(_minter1, newCollateral, newTimestamp, "", _validator1Pk);
        address[] memory validators = new address[](1);
        validators[0] = _validator1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        vm.expectEmit();
        emit PenaltyAccrued(_minter1, penalty, _minter1);
        _protocol.updateCollateral(newCollateral, newTimestamp, "", validators, signatures);

        uint256 expectedPenalty = (((minterOutstandingValue + penalty) - (newCollateral * _mintRatio) / ONE) *
            _penalty) / ONE;

        // precision loss of 2 wei-s - 1 per each penalty
        assertEq(_protocol.outstandingValueOf(_minter1) + 2 wei, minterOutstandingValue + penalty + expectedPenalty);

        (, uint256 lastUpdated_, uint256 penalizedUntil_) = _protocol.collateralOf(_minter1);

        assertEq(lastUpdated_, newTimestamp);
        assertEq(penalizedUntil_, newTimestamp);
    }

    function test_burn_accruePenaltyForExpiredCollateralValue() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setNormalizedPrincipalOf(_minter1, amount);

        vm.warp(timestamp + 3 * _updateCollateralInterval);

        uint256 penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        uint256 minterOustandingValue = _protocol.outstandingValueOf(_minter1);
        assertEq(penalty, (minterOustandingValue * 3 * _penalty) / ONE);

        _mintTo(to, minterOustandingValue);

        vm.prank(to);
        vm.expectEmit();
        emit PenaltyAccrued(_minter1, penalty, to);
        _protocol.burn(_minter1, minterOustandingValue);

        minterOustandingValue = _protocol.outstandingValueOf(_minter1);

        assertEq(minterOustandingValue, penalty);
    }

    function test_accruePenalty_penalizedUntil() external {
        uint256 collateral = 100e18;
        uint256 amount = 60e18;
        uint256 timestamp = block.timestamp;

        _protocol.setCollateralOf(_minter1, collateral, timestamp);
        _protocol.setNormalizedPrincipalOf(_minter1, amount);

        vm.warp(timestamp + _updateCollateralInterval - 10);

        uint256 penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        assertEq(penalty, 0);

        vm.warp(timestamp + _updateCollateralInterval + 10);

        penalty = _protocol.getUnaccruedPenaltyForExpiredCollateralValue(_minter1);
        assertEq(penalty, (_protocol.outstandingValueOf(_minter1) * _penalty) / ONE);

        bytes memory signature = _getSignature(_minter1, collateral, block.timestamp, "", _validator1Pk);
        address[] memory validators = new address[](1);
        validators[0] = _validator1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(_minter1);
        _protocol.updateCollateral(collateral, block.timestamp, "", validators, signatures);

        (, uint256 lastUpdated, uint256 penalizedUntil) = _protocol.collateralOf(_minter1);
        assertEq(lastUpdated, block.timestamp);
        assertEq(penalizedUntil, timestamp + _updateCollateralInterval);

        address to = makeAddr("to");
        _mintTo(to, 10e18);

        vm.prank(to);
        _protocol.burn(_minter1, 10e18);

        (, uint256 lastUpdatedAgain, uint256 penalizedUntilAgain) = _protocol.collateralOf(_minter1);
        assertEq(lastUpdated, lastUpdatedAgain);
        assertEq(penalizedUntilAgain, penalizedUntilAgain);
    }

    function _mintTo(address account, uint256 amount) internal {
        vm.prank(address(_protocol));
        _mToken.mint(account, amount);
    }

    function _getSignature(
        address minter,
        uint amount,
        uint timestamp,
        string memory metadata,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = DigestHelper.getUpdateCollateralDigest(
            address(_protocol),
            minter,
            amount,
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
