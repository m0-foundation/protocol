// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { MToken } from "../../../src/MToken.sol";

contract MTokenHarness is MToken {
    constructor(address spogRegistrar_, address protocol_) MToken(spogRegistrar_, protocol_) {}

    function getter_balance(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function setter_isEarning(address account_, bool isEarning_) external {
        _isEarning[account_] = isEarning_;
    }

    function getter_totalPrincipalOfEarningSupply() external view returns (uint256 totalPrincipalOfEarningSupply_) {
        return _totalPrincipalOfEarningSupply;
    }

    function external_getPresentAmountAndUpdateIndex(uint256 principalAmount_) external returns (uint256 presentAmount_) {
        return _getPresentAmountAndUpdateIndex(principalAmount_);
    }

    function external_getPrincipalAmountAndUpdateIndex(uint256 presentAmount_) external returns (uint256 principalAmount_) {
        return _getPrincipalAmount(presentAmount_, updateIndex());
    }

    function external_getPresentAmount(uint256 principalAmount_,uint256 index_) external pure returns (uint256 presentAmount_) {
        return _getPresentAmount(principalAmount_, index_);
    }

    function external_getPrincipalAmount(uint256 presentAmount_, uint256 index_) external pure returns (uint256 principalAmount_) {
        return _getPresentAmount(presentAmount_, index_);
    }

    function external_rate() external view virtual returns (uint256 rate_) {
        return _rate();
    }
}
