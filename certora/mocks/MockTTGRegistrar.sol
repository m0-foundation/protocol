// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ITTGRegistrar } from "../../src/interfaces/ITTGRegistrar.sol";

contract MockTTGRegistrar is ITTGRegistrar {
    address internal _vault;

    mapping(bytes32 list => mapping(address account => bool isInList)) internal _isInList;
    mapping(bytes32 key => bytes32 value) internal _values;

    function addToList(bytes32 list_, address account_) external {
        _isInList[list_][account_] = true;
    }

    function removeFromList(bytes32 list_, address account_) external {
        _isInList[list_][account_] = false;
    }

    function get(bytes32 key_) external view returns (bytes32) {
        return _values[key_];
    }

    function listContains(bytes32 list_, address account_) external view returns (bool) {
        return _isInList[list_][account_];
    }

    function setVault(address vault_) external {
        _vault = vault_;
    }

    function updateConfig(bytes32 key_, address value_) external {
        _values[key_] = bytes32(uint256(uint160(value_)));
    }

    function updateConfig(bytes32 key_, uint256 value_) external {
        _values[key_] = bytes32(value_);
    }

    function updateConfig(bytes32 key_, bytes32 value_) external {
        _values[key_] = value_;
    }

    function vault() external view returns (address) {
        return _vault;
    }
}
