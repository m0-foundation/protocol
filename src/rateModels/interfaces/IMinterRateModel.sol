// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../../interfaces/IRateModel.sol";

/// @title Minter Rate Model Interface.
interface IMinterRateModel is IRateModel {
    /// @notice Emitted when TTG Registrar contract address is zero.
    error ZeroTTGRegistrar();

    /// @notice The TTG Registrar contract address.
    function ttgRegistrar() external view returns (address);

    /// @notice The base rate of the Minter Rate Model.
    function baseRate() external view returns (uint256);
}
