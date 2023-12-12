// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address spogRegistrar_, address protocol_) MToken(spogRegistrar_, protocol_) {}

    function setLatestIndex(uint256 index_) external {
        _latestIndex = uint128(index_);
    }

    function setLatestRate(uint256 rate_) external {
        _latestRate = uint32(rate_);
    }

    function setLatestUpdated(uint256 timestamp_) external {
        _latestUpdateTimestamp = uint40(timestamp_);
    }

    function setIsEarning(address account_, bool isEarning_) external {
        _isEarning[account_] = isEarning_;
    }

    function setHasOptedOutOfEarning(address account_, bool hasOptedOut_) external {
        _hasOptedOutOfEarning[account_] = hasOptedOut_;
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        _totalNonEarningSupply = uint128(totalNonEarningSupply_);
    }

    function setTotalPrincipalOfEarningSupply(uint256 totalPrincipalOfEarningSupply_) external {
        _totalPrincipalOfEarningSupply = uint128(totalPrincipalOfEarningSupply_);
    }

    function setInternalBalanceOf(address account_, uint256 balance_) external {
        _balances[account_] = uint128(balance_);
    }

    function internalBalanceOf(address account_) external view returns (uint128 balance_) {
        return _balances[account_];
    }

    function totalPrincipalOfEarningSupply() external view returns (uint128 totalPrincipalOfEarningSupply_) {
        return _totalPrincipalOfEarningSupply;
    }

    function rate() external view returns (uint32 rate_) {
        return _rate();
    }
}
