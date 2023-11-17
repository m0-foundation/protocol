// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import "../../src/interfaces/ISPOGRegistrar.sol";

contract MockSPOGRegistrar is ISPOGRegistrar {
    address internal _vault;

    mapping(bytes32 key => bytes32 value) internal _valueAt;

    function addToList(bytes32 list_, address account_) external {
        _valueAt[_getKeyInSet(list_, account_)] = bytes32(uint256(1));
    }

    function get(bytes32 key_) external view returns (bytes32) {
        return _valueAt[key_];
    }

    function listContains(bytes32 list_, address account_) external view returns (bool) {
        return _valueAt[_getKeyInSet(list_, account_)] == bytes32(uint256(1));
    }

    function removeFromList(bytes32 list_, address account_) external {
        delete _valueAt[_getKeyInSet(list_, account_)];
    }

    function setVault(address vault_) external {
        _vault = vault_;
    }

    function updateConfig(bytes32 key_, address value_) external {
        _valueAt[key_] = bytes32(uint256(uint160(value_)));
    }

    function updateConfig(bytes32 key_, uint256 value_) external {
        _valueAt[key_] = bytes32(value_);
    }

    function updateConfig(bytes32 key_, bytes32 value_) external {
        _valueAt[key_] = value_;
    }

    function vault() external view returns (address) {
        return _vault;
    }

    function _getKeyInSet(bytes32 list_, address account_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(list_, account_));
    }
}

contract MockMToken {
    bool internal _burnFail;

    uint256 internal _currentIndex;
    uint256 internal _totalSupply;

    function mint(address account_, uint256 amount_) external {}

    function burn(address /*account_*/, uint256 /*amount_*/) external view {
        if (_burnFail) revert();
    }

    function setBurnFail(bool fail_) external {
        _burnFail = fail_;
    }

    function setCurrentIndex(uint256 index_) external {
        _currentIndex = index_;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function updateIndex() public virtual returns (uint256 currentIndex_) {
        return _currentIndex;
    }

    function updateRate() public virtual returns (uint256 rate_) {
        return rate_;
    }

    function totalSupply() external view returns (uint256 totalSupply_) {
        return _totalSupply;
    }
}

contract MockProtocol {
    uint256 internal _minterRate;
    uint256 internal _totalActiveOwedM;

    function setMinterRate(uint256 minterRate_) external {
        _minterRate = minterRate_;
    }

    function setTotalActiveOwedM(uint256 totalActiveOwedM_) external {
        _totalActiveOwedM = totalActiveOwedM_;
    }

    function minterRate() external view returns (uint256 minterRate_) {
        return _minterRate;
    }

    function totalActiveOwedM() external view returns (uint256 totalActiveOwedM_) {
        return _totalActiveOwedM;
    }
}

contract MockRateModel {
    uint256 public rate;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }
}
