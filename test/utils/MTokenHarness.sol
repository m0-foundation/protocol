// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address protocol_, address spogRegistrar_) MToken(protocol_, spogRegistrar_) {}

    function setIndex(uint256 index_) external {
        _index = index_;
    }

    function setLastUpdated(uint256 lastUpdated_) external {
        _lastUpdated = lastUpdated_;
    }

    function setIsEarning(address account_, bool isEarning_) external {
        _isEarning[account_] = isEarning_;
    }

    function setHasOptedOut(address account_, bool hasOptedOut_) external {
        _hasOptedOut[account_] = hasOptedOut_;
    }

    function setInternalTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function setTotalEarningSupplyPrincipal(uint256 totalEarningSupplyPrincipal_) external {
        _totalEarningSupplyPrincipal = totalEarningSupplyPrincipal_;
    }

    function setInternalBalanceOf(address account_, uint256 balance_) external {
        _balances[account_] = balance_;
    }

    function index() external view returns (uint256 index_) {
        return _index;
    }

    function currentIndex() external view returns (uint256 index_) {
        return _currentIndex();
    }

    function lastUpdated() external view returns (uint256 lastUpdated_) {
        return _lastUpdated;
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function totalEarningSupplyPrincipal() external view returns (uint256 totalSupply_) {
        return _totalEarningSupplyPrincipal;
    }

    function internalTotalSupply() external view returns (uint256 totalSupply_) {
        return _totalSupply;
    }
}
