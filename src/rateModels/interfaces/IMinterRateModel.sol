// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../../interfaces/IRateModel.sol";

/**
 * @title Minter Rate Model Interface.
 * @author M^0 Labs
 */
interface IMinterRateModel is IRateModel {
    /* ============ Custom Errors ============ */

    /// @notice Emitted when TTG Registrar contract address is zero.
    error ZeroTTGRegistrar();

    /* ============ View/Pure Functions ============ */

    /// @notice The TTG Registrar contract address.
    function ttgRegistrar() external view returns (address);
}
