// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../../interfaces/IRateModel.sol";

/// @title Earner Rate Model Interface.
interface IEarnerRateModel is IRateModel {
    /// @notice Emitted when M Token contract address is zero.
    error ZeroMToken();

    /// @notice Emitted when Minter Gateway contract address is zero.
    error ZeroMinterGateway();

    /// @notice Emitted when TTG Registrar contract address is zero.
    error ZeroTTGRegistrar();

    /// @notice The M Token contract address.
    function mToken() external view returns (address);

    /// @notice The Minter Gateway contract address.
    function minterGateway() external view returns (address);

    /// @notice The TTG Registrar contract address.
    function ttgRegistrar() external view returns (address);

    /// @notice The base rate of the Earner Rate Model.
    function baseRate() external view returns (uint256);
}
