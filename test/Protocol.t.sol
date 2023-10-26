// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { ContractHelper } from "../src/libs/ContractHelper.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { MockSPOG } from "./utils/Mocks.sol";
import { DigestHelper } from "./utils/DigestHelper.sol";
import { MToken } from "../src/MToken.sol";
import { ProtocolHarness } from "./utils/ProtocolHarness.sol";

contract ProtocolTests is Test {
    address internal _minter1;
    uint256 internal _minter1Pk;

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralQuorum = 1;
    uint256 internal _updateCollateralInterval = 20;
    uint256 internal _minterFreezeTime = 1000;
    uint256 internal _mintRequestQueueTime = 1000;
    uint256 internal _mintRequestTtl = 1500;

    MockSPOG internal _spog;
    MToken internal _mToken;
    ProtocolHarness internal _protocol;

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);
    event MintRequestedCreated(address indexed minter, uint256 amount, address indexed to);
    event MintRequestExecuted(address indexed minter, uint256 amount, address indexed to);
    event MintRequestCanceled(address indexed minter, address indexed canceller);
    event MinterFrozen(address indexed minter, uint256 frozenUntil);

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator1");

        // Initiate protocol and M token, use ContractHelper to solve circular dependeny.
        _spog = new MockSPOG();
        address expectedProtocol_ = ContractHelper.getContractFrom(address(this), vm.getNonce(address(this)) + 1);
        _mToken = new MToken(address(expectedProtocol_));
        _protocol = new ProtocolHarness(address(_spog), address(_mToken));

        _spog.addToList(_protocol.MINTERS_LIST_NAME(), _minter1);
        _spog.addToList(_protocol.VALIDATORS_LIST_NAME(), _validator1);

        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_QUORUM(), bytes32(_updateCollateralQuorum));
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_INTERVAL(), bytes32(_updateCollateralInterval));

        _spog.updateConfig(_protocol.MINTER_FREEZE_TIME(), bytes32(_minterFreezeTime));
        _spog.updateConfig(_protocol.MINT_REQUEST_QUEUE_TIME(), bytes32(_mintRequestQueueTime));
        _spog.updateConfig(_protocol.MINT_REQUEST_TTL(), bytes32(uint256(_mintRequestTtl)));
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
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_QUORUM(), bytes32(uint256(3)));
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;

        bytes memory signature1 = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);
        bytes memory signature2 = _getSignature(_minter1, collateral, timestamp, "", _validator2Pk);

        address[] memory validators = new address[](3);
        validators[0] = _validator1;
        validators[1] = _validator1;
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
        uint256 amount = 200e2;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateral(_minter1, amount, timestamp);

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestedCreated(_minter1, amount, to);
        _protocol.proposeMint(amount, to);

        (uint256 amount_, uint256 timestamp_, address to_) = _protocol.mintRequests(_minter1);
        assertEq(amount_, amount);
        assertEq(to_, to);
        assertEq(timestamp_, timestamp);
    }

    function test_cancel() external {
        _protocol.setMintRequest(_minter1, 100, block.timestamp, makeAddr("to"));

        vm.prank(_validator1);
        vm.expectEmit();
        emit MintRequestCanceled(_minter1, _validator1);
        _protocol.cancel(_minter1);

        (uint256 amount_, uint256 timestamp_, address to_) = _protocol.mintRequests(_minter1);
        assertEq(amount_, 0);
        assertEq(timestamp_, 0);
        assertEq(to_, address(0));
    }

    function test_cancel_notApprovedValidator() external {
        _protocol.setMintRequest(_minter1, 100, block.timestamp, makeAddr("to"));

        vm.prank(makeAddr("alice"));
        vm.expectRevert(IProtocol.NotApprovedValidator.selector);
        _protocol.cancel(_minter1);
    }

    function test_freeze() external {
        uint256 amount = 100;
        uint256 timestamp = block.timestamp;
        address to = makeAddr("to");

        _protocol.setCollateral(_minter1, amount, timestamp);

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

        vm.prank(_minter1);
        vm.expectEmit();
        emit MintRequestedCreated(_minter1, amount, to);
        _protocol.proposeMint(amount, to);
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

    function test_freeze_notApprovedMinter() external {
        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.freeze(makeAddr("alice"));
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

    function test_updateCollateral_notMinter() external {
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;
        bytes memory signature = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = signature;

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.updateCollateral(_minter1, collateral, block.timestamp, "", validators_, signatures_);
    }

    function test_updateCollateral_invalidMinter() external {
        address[] memory validators_ = new address[](1);
        bytes[] memory signatures_ = new bytes[](1);

        vm.prank(_validator1);
        vm.expectRevert(IProtocol.NotApprovedMinter.selector);
        _protocol.updateCollateral(makeAddr("alice"), 100, block.timestamp, "", validators_, signatures_);
    }

    function test_updateCollateral_invalidSignaturesLength() external {
        bytes memory signature = _getSignature(_minter1, 100, block.timestamp, "", _validator1Pk);

        address[] memory validators_ = new address[](2);
        validators_[0] = _validator1;
        validators_[1] = _validator1;

        bytes[] memory signatures_ = new bytes[](3);
        signatures_[0] = signature;
        signatures_[1] = signature;
        signatures_[2] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.InvalidSignaturesLength.selector);
        _protocol.updateCollateral(_minter1, 100, block.timestamp, "", validators_, signatures_);
    }

    function test_updateCollateral_expiredTimestamp() external {
        uint256 timestamp = block.timestamp - _updateCollateralInterval - 1;
        bytes memory signature = _getSignature(_minter1, 100, timestamp, "", _validator1Pk);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.ExpiredTimestamp.selector);
        _protocol.updateCollateral(_minter1, 100, timestamp, "", validators_, signatures_);
    }

    function test_updateCollateral_staleTimestamp() external {
        bytes memory signature = _getSignature(_minter1, 100, block.timestamp, "", _validator1Pk);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = signature;

        vm.prank(_minter1);
        _protocol.updateCollateral(_minter1, 100, block.timestamp, "", validators_, signatures_);

        (, uint256 lastUpdated_) = _protocol.collateral(_minter1);

        uint256 timestamp = lastUpdated_ - 1;
        signature = _getSignature(_minter1, 100, timestamp, "", _validator1Pk);
        signatures_[0] = signature;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.StaleTimestamp.selector);
        _protocol.updateCollateral(_minter1, 100, timestamp, "", validators_, signatures_);
    }

    function test_updateCollateral_notEnoughValidSignatures() external {
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_QUORUM(), bytes32(uint256(3)));
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;

        bytes memory signature1 = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);
        bytes memory signature2 = _getSignature(_minter1, collateral, timestamp, "", _validator2Pk);

        address[] memory validators_ = new address[](3);
        validators_[0] = _validator1;
        validators_[1] = _validator1;
        validators_[2] = _validator2;

        bytes[] memory signatures_ = new bytes[](3);
        signatures_[0] = signature1;
        signatures_[1] = signature2;
        signatures_[2] = signature2;

        vm.prank(_minter1);
        vm.expectRevert(IProtocol.NotEnoughValidSignatures.selector);
        _protocol.updateCollateral(_minter1, collateral, timestamp, "", validators_, signatures_);
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
}
