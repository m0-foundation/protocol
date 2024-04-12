// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../../interfaces/IRateModel.sol";

/**
 * @title  Earner Rate Model Interface.
 * @author M^0 Labs
 */
interface IEarnerRateModel is IRateModel {
    /* ============ Custom Errors ============ */

    /// @notice Emitted when M Token contract address is zero.
    error ZeroMToken();

    /// @notice Emitted when Minter Gateway contract address is zero.
    error ZeroMinterGateway();

    /// @notice Emitted when TTG Registrar contract address is zero.
    error ZeroTTGRegistrar();

    /* ============ View/Pure Functions ============ */

    /// @notice The interval over which there's confidence cash flow to earners will not exceed cash flows from minters.
    function RATE_CONFIDENCE_INTERVAL() external view returns (uint32);

    /// @notice The percent (in basis points) of the earner rate that will be effectively used.
    function RATE_MULTIPLIER() external view returns (uint32);

    /// @notice 100% in basis points.
    function ONE() external view returns (uint32);

    /// @notice The M Token contract address.
    function mToken() external view returns (address);

    /// @notice The Minter Gateway contract address.
    function minterGateway() external view returns (address);

    /// @notice The TTG Registrar contract address.
    function ttgRegistrar() external view returns (address);

    /// @notice The max rate in basis points.
    function maxRate() external view returns (uint256);

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
