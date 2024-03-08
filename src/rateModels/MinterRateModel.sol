// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "../interfaces/IRateModel.sol";
import { IMinterRateModel } from "./interfaces/IMinterRateModel.sol";
import { ITTGRegistrar } from "../interfaces/ITTGRegistrar.sol";

/**
 * @title  Minter Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by Minter Gateway.
 * @author M^0 Labs
 */
contract MinterRateModel is IMinterRateModel {
    /* ============ Variables ============ */

    /// @notice The name of parameter in TTG that defines the base minter rate.
    bytes32 internal constant _BASE_MINTER_RATE = "base_minter_rate";

    /// @inheritdoc IMinterRateModel
    address public immutable ttgRegistrar;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the MinterRateModel contract.
     * @param ttgRegistrar_ The address of the TTG Registrar contract.
     */
    constructor(address ttgRegistrar_) {
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256 rate_) {
        return uint256(ITTGRegistrar(ttgRegistrar).get(_BASE_MINTER_RATE));
    }
}
