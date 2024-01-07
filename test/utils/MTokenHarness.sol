// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address ttgRegistrar_, address minterGateway_) MToken(ttgRegistrar_, minterGateway_) {}

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
        _balances[account_].isEarning = isEarning_;
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        _totalNonEarningSupply = uint128(totalNonEarningSupply_);
    }

    function setPrincipalOfTotalEarningSupply(uint256 principalOfTotalEarningSupply_) external {
        _principalOfTotalEarningSupply = uint112(principalOfTotalEarningSupply_);
    }

    function setInternalBalanceOf(address account_, uint256 balance_) external {
        _balances[account_].rawBalance = uint128(balance_);
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_].rawBalance;
    }

    function principalOfTotalEarningSupply() external view returns (uint128 principalOfTotalEarningSupply_) {
        return _principalOfTotalEarningSupply;
    }

    function rate() external view returns (uint32 rate_) {
        return _rate();
    }
}
