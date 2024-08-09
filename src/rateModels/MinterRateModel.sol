// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { IRateModel } from "../interfaces/IRateModel.sol";
import { IMinterRateModel } from "./interfaces/IMinterRateModel.sol";
import { IRegistrar } from "../interfaces/IRegistrar.sol";

/**
 * @title  Minter Rate Model contract set in the Registrar and accessed by the Minter Gateway.
 * @author M^0 Labs
 */
contract MinterRateModel is IMinterRateModel {
    /* ============ Variables ============ */

    /// @notice The name of parameter in the Registrar that defines the base minter rate.
    bytes32 internal constant _BASE_MINTER_RATE = "base_minter_rate";

    /// @notice The maximum allowed rate in basis points.
    uint256 public constant MAX_MINTER_RATE = 40_000; // 400%

    /// @inheritdoc IMinterRateModel
    address public immutable registrar;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs MinterRateModel.
     * @param  registrar_ The address of the Registrar contract.
     */
    constructor(address registrar_) {
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256 rate_) {
        return UIntMath.min256(uint256(IRegistrar(registrar).get(_BASE_MINTER_RATE)), MAX_MINTER_RATE);
    }
}
