// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { Protocol } from "../src/Protocol.sol";

import { MockSPOG } from "./utils/Mocks.sol";
import { DigestHelper } from "./utils/DigestHelper.sol";

contract ProtocolTests is Test {
    address internal _minter1;
    uint256 internal _minter1Pk;

    address internal _validator1;
    uint256 internal _validator1Pk;
    address internal _validator2;
    uint256 internal _validator2Pk;

    uint256 internal _updateCollateralQuorum = 1;
    uint256 internal _updateCollateralInterval = 20;

    MockSPOG internal _spog;
    Protocol internal _protocol;

    event CollateralUpdated(address indexed minter, uint256 amount, uint256 timestamp, string metadata);

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");
        (_validator2, _validator2Pk) = makeAddrAndKey("validator1");

        _spog = new MockSPOG();
        _protocol = new Protocol(address(_spog));

        _spog.addToList(_protocol.MINTERS_LIST_NAME(), _minter1);
        _spog.addToList(_protocol.VALIDATORS_LIST_NAME(), _validator1);
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_QUORUM(), bytes32(_updateCollateralQuorum));
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_INTERVAL(), bytes32(_updateCollateralInterval));
    }

    function test_updateCollateral() external {
        uint256 collateral = 100;
        uint256 timestamp = block.timestamp;
        bytes memory signature = _getSignature(_minter1, collateral, timestamp, "", _validator1Pk);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = signature;

        vm.prank(_minter1);
        vm.expectEmit();
        emit CollateralUpdated(_minter1, collateral, timestamp, "");
        _protocol.updateCollateral(_minter1, collateral, block.timestamp, "", validators_, signatures_);

        (uint256 amount_, uint256 lastUpdated_) = _protocol.collateral(_minter1);
        assertEq(amount_, collateral);
        assertEq(lastUpdated_, timestamp);
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
