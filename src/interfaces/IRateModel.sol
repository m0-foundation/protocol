// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

/// @title Rate Model Interface.
interface IRateModel {
    /**
     * @notice Returns the current yearly rate in BPS.
     *         This value does not account for the compounding interest.
     */
    function rate() external view returns (uint256);
}
