// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IInterestRateModel {
    /**
     * @notice Returns the current value of interest rate
     * @dev APY in BPS
     */
    function rate() external view returns (uint256);
}
