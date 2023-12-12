// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

interface IRateModel {
    /**
     * @notice Returns the current value of the yearly rate
     * @dev    APY in BPS
     */
    function rate() external view returns (uint256 rate);
}
