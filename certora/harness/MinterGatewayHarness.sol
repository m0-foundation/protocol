// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;
import "../../src/MinterGateway.sol";

contract MinterGatewayHarness is MinterGateway {
    constructor(address ttgRegistrar_, address mToken_) MinterGateway(ttgRegistrar_, mToken_) {}

    function totalMSupply() public view returns (uint240) {
        // Note this is also used to determine the total M supply in
        // functions implemented in MinterGatway
        return uint240(IMToken(mToken).totalSupply()); 
    }

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/

    function getLatestIndexInMinterGateway() public view returns (uint128) {
        return latestIndex;
    }

    function getLatestRateInMinterGateway() public view returns (uint32) {
        return _latestRate;
    }

    function getLatestUpdateTimestampInMinterGateway() public view returns (uint40) {
        return latestUpdateTimestamp;
    }

    function getPrincipalAmountRoundedDown(uint240 amount_) public view returns (uint112 principalAmount_) {
        return _getPrincipalAmountRoundedDown(amount_);
    }

    function getPrincipalAmountRoundedUp(uint240 amount_) public view returns (uint112 principalAmount_) {
        return _getPrincipalAmountRoundedUp(amount_);
    }

    function getMinterRate() public view returns (uint32) {
        return _rate();
    }

    function getPresentAmount(uint112 principalAmount_) public view returns (uint240) {
        return _getPresentAmount(principalAmount_);
    }
}
