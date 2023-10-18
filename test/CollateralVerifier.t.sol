// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { console2, Test } from "../lib/forge-std/src/Test.sol";

import { CollateralVerifier } from "../src/CollateralVerifier.sol";

contract CollateralVerifierTests is Test {
    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");

    CollateralVerifier internal _verifier;

    // MockSPOG internal _spog;

    function setUp() external {
        // _spog = new MockSPOG();
        _verifier = new CollateralVerifier();
    }

    function test() external {
        (address charlie, uint256 charliePk) = makeAddrAndKey("charlie");
        uint256 collateral = 1000e18;
        uint256 timestamp = 1000;
        bytes32 validationDigest = _verifier.getValidationDigest(_alice, collateral, "hello", timestamp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(charliePk, validationDigest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(charlie, _alice, collateral, "hello", timestamp, signature);

        (address minter, uint256 decodedCollateral, uint256 decodedTimestamp) = _verifier.decode(address(0), data);
        assertEq(minter, _alice);
        assertEq(collateral, decodedCollateral);
        assertEq(timestamp, decodedTimestamp);
        console2.log("minter = ", minter);
        console2.logBytes(signature);
    }
}
