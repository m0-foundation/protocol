// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "../../src/interfaces/ISPOG.sol";

contract MockSPOG is ISPOG {
    mapping(bytes32 key => bytes32 value) internal _valueAt;

    function get(bytes32 key) external view returns (bytes32 value) {}

    function listContains(bytes32 list, address account) external view returns (bool contains) {}
}
