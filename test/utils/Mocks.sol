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

contract MockMToken {
    bool internal _burnFail;

    uint256 internal _currentIndex;
    uint256 internal _totalSupply;

    function mint(address account_, uint256 amount_) external {}

    function burn(address account_, uint256 amount_) external {}

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

contract MockMinterGateway {
    address public mToken;
    address public ttgRegistrar;

    uint256 public minterRate;
    uint256 public totalActiveOwedM;

    function setMToken(address mToken_) external {
        mToken = mToken_;
    }

    function setMinterRate(uint256 minterRate_) external {
        minterRate = minterRate_;
    }

    function setTotalActiveOwedM(uint256 totalActiveOwedM_) external {
        totalActiveOwedM = totalActiveOwedM_;
    }

    function setTtgRegistrar(address ttgRegistrar_) external {
        ttgRegistrar = ttgRegistrar_;
    }
}

contract MockRateModel {
    uint256 public rate;

    function setRate(uint256 rate_) external {
        rate = rate_;
    }
}
