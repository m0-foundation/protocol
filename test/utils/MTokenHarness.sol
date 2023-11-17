// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address spogRegistrar_, address protocol_) MToken(spogRegistrar_, protocol_) {}

    function setLatestIndex(uint256 index_) external {
        _latestIndex = index_;
    }

    function setLatestUpdated(uint256 timestamp_) external {
        _latestUpdateTimestamp = timestamp_;
    }

    function setIsEarning(address account_, bool isEarning_) external {
        _isEarning[account_] = isEarning_;
    }

    function setHasOptedOut(address account_, bool hasOptedOut_) external {
        _hasOptedOutOfEarning[account_] = hasOptedOut_;
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        _totalNonEarningSupply = totalNonEarningSupply_;
    }

    function setTotalPrincipalOfEarningSupply(uint256 totalPrincipalOfEarningSupply_) external {
        _totalPrincipalOfEarningSupply = totalPrincipalOfEarningSupply_;
    }

    function setInternalBalanceOf(address account_, uint256 balance_) external {
        _balances[account_] = balance_;
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function totalPrincipalOfEarningSupply() external view returns (uint256 totalPrincipalOfEarningSupply_) {
        return _totalPrincipalOfEarningSupply;
    }
}
