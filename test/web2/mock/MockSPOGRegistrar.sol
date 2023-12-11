// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {ISPOGRegistrar} from "../../../src/interfaces/ISPOGRegistrar.sol";

contract MockSPOGRegistrar is ISPOGRegistrar
{
    address internal _vault;
    mapping(bytes32 key => bytes32 value) internal _values;
    mapping(bytes32 list => mapping(address account => bool value)) internal _lists;


    function __setValue(bytes32 key_, address value_) external {
        _values[key_] = bytes32(uint256(uint160(value_)));
    }

    function __setValue(bytes32 key_, uint256 value_) external {
        _values[key_] = bytes32(value_);
    }

    function __setValue(bytes32 key_, bytes32 value_) external {
        _values[key_] = value_;
    }

    function __setListValue(bytes32 list_, address account_) external {
        bytes32 key = keccak256(abi.encodePacked(list_, account_));
        _values[key] = bytes32(uint256(1));
    }

    function setVault(address vault_) external {
        _vault = vault_;
    }

    function get(bytes32 key_) external view returns (bytes32) {
        return _values[key_];
    }

    function listContains(bytes32 list_, address account_) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(list_, account_));
        return _values[key] == bytes32(uint256(1));
    }

    function vault() external view returns (address) {
        return _vault;
    }




}
