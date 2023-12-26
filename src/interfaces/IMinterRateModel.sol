// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "./IRateModel.sol";

/// @title Minter Rate Model Interface.
interface IMinterRateModel is IRateModel {
    /// @notice Emitted when SPOG Registrar contract address is zero.
    error ZeroSpogRegistrar();

    /// @notice The SPOG Registrar contract address.
    function spogRegistrar() external view returns (address);

    /// @notice The base rate of the Earner Rate Model.
    function baseRate() external view returns (uint256);
}
