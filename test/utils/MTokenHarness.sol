// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address registrar_) MToken(registrar_) {}

    function setLatestIndex(uint256 index_) external {
        latestIndex = uint128(index_);
    }

    function setLatestUpdated(uint256 timestamp_) external {
        latestUpdateTimestamp = uint40(timestamp_);
    }

    function setIsEarning(address account_, bool isEarning_) external {
        _balances[account_].isEarning = isEarning_;
    }

    function setTotalNonEarningSupply(uint256 totalNonEarningSupply_) external {
        totalNonEarningSupply = uint240(totalNonEarningSupply_);
    }

    function setPrincipalOfTotalEarningSupply(uint256 principalOfTotalEarningSupply_) external {
        principalOfTotalEarningSupply = uint112(principalOfTotalEarningSupply_);
    }

    function setInternalBalanceOf(address account_, uint256 balance_) external {
        _balances[account_].rawBalance = uint240(balance_);
    }

    function internalBalanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_].rawBalance;
    }
}
