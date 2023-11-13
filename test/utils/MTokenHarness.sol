// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address protocol_, address spogRegistrar_) MToken(protocol_, spogRegistrar_) {}

    function setInterestIndex(uint256 interestIndex_) external {
        _interestIndex = interestIndex_;
    }

    function setLastUpdated(uint256 lastUpdated_) external {
        _lastUpdated = lastUpdated_;
    }

    function setIsEarningInterest(address account_, bool isEarningInterest_) external {
        _isEarningInterest[account_] = isEarningInterest_;
    }

    function setInternalTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function setInterestEarningTotalSupply(uint256 interestEarningTotalSupply_) external {
        _interestEarningTotalSupply = interestEarningTotalSupply_;
    }

    function setInternalBalance(address account_, uint256 balance_) external {
        _balances[account_] = balance_;
    }

    function interestIndex() external view returns (uint256 interestIndex_) {
        return _interestIndex;
    }

    function currentInterestIndex() external view returns (uint256 interestIndex_) {
        return _currentInterestIndex();
    }

    function lastUpdated() external view returns (uint256 lastUpdated_) {
        return _lastUpdated;
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function interestEarningTotalSupply() external view returns (uint256 totalSupply_) {
        return _interestEarningTotalSupply;
    }

    function internalTotalSupply() external view returns (uint256 totalSupply_) {
        return _totalSupply;
    }
}
