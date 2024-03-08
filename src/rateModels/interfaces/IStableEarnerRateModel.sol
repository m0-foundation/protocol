// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IEarnerRateModel } from "./IEarnerRateModel.sol";

/**
 * @title  Earner Rate Model Interface.
 * @author M^0 Labs
 */
interface IStableEarnerRateModel is IEarnerRateModel {
    /* ============ View/Pure Functions ============ */

    /// @notice The interval over which there's confidence cash flow to earners will not exceed cash flows from minters.
    function RATE_CONFIDENCE_INTERVAL() external view returns (uint32);

    /// @notice The percent (in basis points) of the earner rate that will be effectively used.
    function RATE_MULTIPLIER() external view returns (uint32);

    /// @notice 100% in basis points.
    function ONE() external view returns (uint32);

    /**
     * @notice Returns the safe earner rate.
     * @param  totalActiveOwedM   The total active owed M.
     * @param  totalEarningSupply The total earning supply of M Token.
     * @param  minterRate         The minter rate.
     * @return The safe earner rate.
     */
    function getSafeEarnerRate(
        uint240 totalActiveOwedM,
        uint240 totalEarningSupply,
        uint32 minterRate
    ) external pure returns (uint32);
}
