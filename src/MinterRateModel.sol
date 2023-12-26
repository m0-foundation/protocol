// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IMinterRateModel } from "./interfaces/IMinterRateModel.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";

/**
 * @title Minter Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by Protocol.
 * @author M^ZERO LABS_
 */
contract MinterRateModel is IMinterRateModel {
    /// @inheritdoc IMinterRateModel
    address public immutable spogRegistrar;

    /**
     * @notice Constructs the MinterRateModel contract.
     * @param spogRegistrar_ The address of the SPOG Registrar contract.
     */
    constructor(address spogRegistrar_) {
        if ((spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
    }

    /// @inheritdoc IMinterRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return SPOGRegistrarReader.getBaseMinterRate(spogRegistrar);
    }

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256 rate_) {
        return baseRate();
    }
}
