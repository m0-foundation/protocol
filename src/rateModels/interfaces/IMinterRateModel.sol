// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../../interfaces/IRateModel.sol";

/**
 * @title  Minter Rate Model Interface.
 * @author M^0 Labs
 */
interface IMinterRateModel is IRateModel {
    /* ============ Custom Errors ============ */

    /// @notice Emitted when the Registrar address is zero.
    error ZeroRegistrar();

    /* ============ View/Pure Functions ============ */

    /// @notice The Registrar address.
    function registrar() external view returns (address);
}
