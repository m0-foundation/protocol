// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;
import "../../src/MToken.sol";


contract MTokenHarness is MToken {

    constructor(address ttgRegistrar_, address minterGateway_) MToken(ttgRegistrar_, minterGateway_) {}

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/


    function getLatestIndexInMToken() public view returns (uint128) {
        return latestIndex;
    }

    function getLatestRateInMToken() public view returns (uint32) {
        return _latestRate;
    }

    function getLatestUpdateTimestampInMToken() public view returns (uint40) {
        return latestUpdateTimestamp;
    }

    function getIsEarning(address account_) public view returns (bool) {
        return _balances[account_].isEarning;
    }

    function getInternalBalanceOf(address account_) public view returns (uint240) {
        return _balances[account_].rawBalance;
    }

    function getEarnerRate() public view returns (uint32) {
        return _rate();
    }
}
