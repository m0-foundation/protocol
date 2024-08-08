// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { MToken } from "../../src/MToken.sol";

contract MTokenHarness is MToken {

    constructor(address registrar_) MToken(registrar_) {}

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/


    function getLatestIndexInMToken() public view returns (uint128) {
        return latestIndex;
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
}
