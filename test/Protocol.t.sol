// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

import { ContractHelper } from "../src/libs/ContractHelper.sol";
import { InterestMath } from "../src/libs/InterestMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { MToken } from "../src/MToken.sol";
import { MockSPOGRegistrar, MockBorrowRateModel } from "./utils/Mocks.sol";
import { DigestHelper } from "./utils/DigestHelper.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

contract ProtocolTests is Test {
    address internal _minter1;
    uint256 internal _minter1Pk;

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralQuorum = 1;
    uint256 internal _updateCollateralInterval = 2000;
    uint256 internal _minterFreezeTime = 1000;
    uint256 internal _mintRequestQueueTime = 1000;
    uint256 internal _mintRequestTtl = 500;
    uint256 internal _borrowRate = 400; // 4%, bps
    uint256 internal _minRatio = 9000; // 90%, bps

    MockSPOGRegistrar internal _spogRegistrar;
    MToken internal _mToken;
    ProtocolHarness internal _protocol;
    MockBorrowRateModel internal _borrowRateModel;

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    event MintRequestedCreated(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(uint256 mintId, address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(uint256 mintId, address indexed minter, address indexed canceller);
    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    event Burn(address indexed minter, address indexed payer, uint256 amount);

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator1");

        // Initiate protocol and M token, use ContractHelper to solve circular dependeny.
        _spogRegistrar = new MockSPOGRegistrar();
        address expectedProtocol_ = ContractHelper.getContractFrom(address(this), vm.getNonce(address(this)) + 1);
        _mToken = new MToken(address(expectedProtocol_));
        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST_NAME, _minter1);
        _spogRegistrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST_NAME, _validator1);

        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM, bytes32(_updateCollateralQuorum));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, bytes32(_updateCollateralInterval));

        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, bytes32(_minterFreezeTime));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_REQUEST_QUEUE_TIME, bytes32(_mintRequestQueueTime));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_REQUEST_TTL, bytes32(_mintRequestTtl));
        _spogRegistrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, bytes32(_minRatio));

        _borrowRateModel = new MockBorrowRateModel();
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BORROW_RATE_MODEL, _toBytes32(address(_borrowRateModel)));
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

        (uint256 amount, uint256 lastUpdated) = _protocol.collateral(_minter1);
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

        (, uint256 lastUpdated_) = _protocol.collateral(_minter1);

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

        _protocol.setCollateral(_minter1, collateral, timestamp);

        vm.pauseGasMetering();
        uint256 expectedMintId = uint256(keccak256(abi.encode(_minter1, amount, to, timestamp, gasleft())));

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestedCreated(expectedMintId, _minter1, amount, to);
        uint256 mintId = _protocol.proposeMint(amount, to);
        assertEq(mintId, expectedMintId);

        vm.resumeGasMetering();

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequests(_minter1);
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

        _protocol.setCollateral(_minter1, collateral, timestamp);

        vm.warp(timestamp + _mintRequestQueueTime);

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

        _protocol.setCollateral(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintRequest(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintRequestQueueTime);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestExecuted(mintId, _minter1, amount, to);
        _protocol.mint(mintId);

        // check that mint request has been deleted
        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequests(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);

        // check that normalizedPrincipal has been updated
        assertTrue(_protocol.normalizedPrincipal(_minter1) > 0);

        // check that balance `to` has been increased
        assertEq(_mToken.balanceOf(to), amount);
    }

    function test_mint_debtOf() external {
        uint256 collateralAmount = 10000e18;
        uint256 mintAmount = 1000000e6;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        // initiate harness functions
        _protocol.setCollateral(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintRequest(_minter1, mintAmount, timestamp, to, 1);

        vm.warp(timestamp + _mintRequestQueueTime);

        vm.prank(_minter1);
        _protocol.mint(mintId);

        uint256 initialDebt = _protocol.debtOf(_minter1);
        uint256 initialIndex = _protocol.mIndex();
        uint256 minterNormalizedPrincipal = _protocol.normalizedPrincipal(_minter1);

        assertEq(initialDebt + 1 wei, mintAmount);

        vm.warp(timestamp + _mintRequestQueueTime + 1);

        uint256 indexAfter1Second = (InterestMath.exponent(_borrowRate, 1) * initialIndex) / 1e18;
        uint256 expectedResult = (minterNormalizedPrincipal * indexAfter1Second) / 1e18;
        assertEq(_protocol.debtOf(_minter1), expectedResult);

        vm.warp(timestamp + _mintRequestQueueTime + 31_536_000);

        uint256 indexAfter1Year = (InterestMath.exponent(_borrowRate, 31_536_000) * initialIndex) / 1e18;
        expectedResult = (minterNormalizedPrincipal * indexAfter1Year) / 1e18;
        assertEq(_protocol.debtOf(_minter1), expectedResult);
    }

    function test_mint_notApprovedMinter() external {
        uint256 mintId = _protocol.setMintRequest(_minter1, 100e18, block.timestamp, makeAddr("to"), 1);

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.mint(mintId);
    }

    function test_mint_frozenMinter() external {
        vm.prank(_validator1);
        _protocol.freeze(_minter1);

        uint256 mintId = _protocol.setMintRequest(_minter1, 100e18, block.timestamp, _minter1, 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.FrozenMinter.selector);
        _protocol.mint(mintId);
    }

    function test_mint_pendingMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintRequest(_minter1, 100, timestamp, makeAddr("to"), 1);

        vm.warp(timestamp + _mintRequestQueueTime / 2);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.PendingMintRequest.selector);
        _protocol.mint(mintId);
    }

    function test_mint_expiredMintRequest() external {
        uint256 timestamp = block.timestamp;
        uint256 mintId = _protocol.setMintRequest(_minter1, 100, timestamp, makeAddr("to"), 1);

        vm.warp(timestamp + _mintRequestQueueTime + _mintRequestTtl + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.ExpiredMintRequest.selector);
        _protocol.mint(mintId);
    }

    function test_mint_undercollateralizedMint() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateral(_minter1, collateral, timestamp);
        uint256 mintId = _protocol.setMintRequest(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintRequestQueueTime + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.UndercollateralizedMint.selector);
        _protocol.mint(mintId);
    }

    function test_mint_undercollateralizedMint_outdatedCollateral() external {
        uint256 collateral = 100e18;
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateral(_minter1, collateral, timestamp - _updateCollateralInterval);
        uint256 mintId = _protocol.setMintRequest(_minter1, amount, timestamp, to, 1);

        vm.warp(timestamp + _mintRequestQueueTime + 1);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.UndercollateralizedMint.selector);
        _protocol.mint(mintId);
    }

    function test_mint_invalidMintRequest() external {
        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.mint(1);
    }

    function test_mint_invalidMintRequest_mistmatchOfIds() external {
        uint256 amount = 95e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");
        uint256 gasLeft = 1;

        uint256 mintId = _protocol.setMintRequest(_minter1, amount, timestamp, to, gasLeft);

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidMintRequest.selector);
        _protocol.mint(mintId - 1);
    }

    function test_cancel_byValidator() external {
        uint256 mintId = _protocol.setMintRequest(_minter1, 100, block.timestamp, makeAddr("to"), 1);

        vm.prank(_validator1);
        vm.expectEmit();
        emit MintRequestCanceled(mintId, _minter1, _validator1);
        _protocol.cancel(_minter1, mintId);

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequests(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);
    }

    function test_cancel_byMinter() external {
        uint256 mintId = _protocol.setMintRequest(_minter1, 100, block.timestamp, makeAddr("to"), 1);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestCanceled(mintId, _minter1, _minter1);
        _protocol.cancel(mintId);

        (uint256 mintId_, address to_, uint256 amount_, uint256 timestamp_) = _protocol.mintRequests(_minter1);
        assertEq(mintId_, 0);
        assertEq(to_, address(0));
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);
    }

    function test_cancel_notApprovedValidator() external {
        uint256 mintId = _protocol.setMintRequest(_minter1, 100, block.timestamp, makeAddr("to"), 1);

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

        _protocol.setCollateral(_minter1, collateral, timestamp);

        uint256 frozenUntil = timestamp + _minterFreezeTime;

        vm.prank(_validator1);
        vm.expectEmit();
        emit MinterFrozen(_minter1, frozenUntil);
        _protocol.freeze(_minter1);

        assertEq(_protocol.frozenUntil(_minter1), frozenUntil);

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

    function test_burn() external {
        uint256 collateralAmount = 10000000e18;
        uint256 mintAmount = 1000000e18;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        // initiate harness functions
        _protocol.setCollateral(_minter1, collateralAmount, timestamp);
        uint256 mintId = _protocol.setMintRequest(_minter1, mintAmount, timestamp, to, 1);

        vm.warp(timestamp + _mintRequestQueueTime);

        vm.prank(_minter1);
        _protocol.mint(mintId);

        vm.prank(to);
        vm.expectEmit();
        // 1 wei precision difference for the benefit of user
        emit Burn(_minter1, to, mintAmount - 1 wei);
        _protocol.burn(_minter1, mintAmount);

        // minter repaid all its debt
        assertEq(_protocol.debtOf(_minter1), 0);
        // 1 wei is left in the user `to`
        assertEq(_protocol.normalizedPrincipal(_minter1), 0);
    }

    function test_burn_repayHalfOfDebt() external {
        uint256 normalizedPrincipal = 100e18;
        _protocol.setNormalizedPrincipal(_minter1, normalizedPrincipal);
        _protocol.setMIndex(1e18);

        uint256 minterDebt = _protocol.debtOf(_minter1);

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        _mintTo(alice, minterDebt);
        _mintTo(bob, minterDebt);

        vm.prank(alice);
        vm.expectEmit();
        emit Burn(_minter1, alice, minterDebt / 2);
        _protocol.burn(_minter1, minterDebt / 2);
        assertEq(_protocol.debtOf(_minter1), minterDebt / 2);
        assertEq(_mToken.balanceOf(alice), minterDebt / 2);

        vm.prank(bob);
        vm.expectEmit();
        emit Burn(_minter1, bob, minterDebt / 2);
        _protocol.burn(_minter1, minterDebt / 2);
        assertEq(_protocol.debtOf(_minter1), 0);
        assertEq(_mToken.balanceOf(alice), minterDebt / 2);
    }

    function test_burn_notEnoughBalanceToRepay() external {
        uint256 normalizedPrincipal = 100e18;
        _protocol.setNormalizedPrincipal(_minter1, normalizedPrincipal);
        _protocol.setMIndex(1e18);

        uint256 minterDebt = _protocol.debtOf(_minter1);

        address alice = makeAddr("alice");
        _mintTo(alice, minterDebt / 2);

        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        _protocol.burn(_minter1, minterDebt);
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
