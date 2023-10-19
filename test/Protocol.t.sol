// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";

import { MockSPOG } from "./utils/Mocks.sol";
import { DigestsHelper } from "./utils/DigestsHelper.sol";

contract ProtocolTests is Test {
    address internal _minter1;
    uint256 internal _minter1Pk;

    address internal _validator1;
    uint256 internal _validator1Pk;

    MockSPOG internal _spog;
    Protocol internal _protocol;

    function setUp() external {
        (_minter1, _minter1Pk) = makeAddrAndKey("minter1");
        (_validator1, _validator1Pk) = makeAddrAndKey("validator1");

        _spog = new MockSPOG();
        _protocol = new Protocol(address(_spog));

        _spog.addToList(_protocol.MINTERS_LIST_NAME(), _minter1);
        _spog.addToList(_protocol.VALIDATORS_LIST_NAME(), _validator1);
        _spog.updateConfig(_protocol.UPDATE_COLLATERAL_QUORUM(), bytes32(uint256(1)));
    }

    function test_updateCollateral() external {
        // signature
        uint256 collateral = 100; // 100 cents here
        uint256 timestamp = block.timestamp;
        bytes32 digest = DigestsHelper.getUpdateCollateralDigest(
            address(_protocol),
            _minter1,
            collateral,
            "",
            timestamp
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_validator1Pk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory validators_ = new address[](1);
        validators_[0] = _validator1;

        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] = signature;

        (uint256 amount_, uint256 lastUpdated_) = _protocol.collateral(_minter1);

        assertEq(amount_, 0);
        assertEq(lastUpdated_, 0);

        vm.prank(_minter1);
        _protocol.updateCollateral(_minter1, collateral, block.timestamp, "", validators_, signatures_);
        (amount_, lastUpdated_) = _protocol.collateral(_minter1);

        assertEq(amount_, collateral);
        assertEq(lastUpdated_, timestamp);
    }
}
