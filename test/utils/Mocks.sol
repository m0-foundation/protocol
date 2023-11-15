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

contract MockRateModel {
    uint256 internal _rate;

    function setRate(uint256 rate_) external {
        _rate = rate_;
    }

    function rate() external view returns (uint256 rate_) {
        return _rate;
    }
}

contract MockMToken {
    bool internal _burnFail;

    uint256 internal _currentIndex;
    uint256 internal _totalSupply;

    function mint(address account_, uint256 amount_) external {}

    function burn(address account_, uint256 amount_) external {
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

    function totalSupply() external view returns (uint256 totalSupply_) {
        return _totalSupply;
    }
}
