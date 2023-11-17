// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IMinterRateModel } from "./interfaces/IMinterRateModel.sol";

contract MinterRateModel is IMinterRateModel {
    address public immutable spogRegistrar;

    constructor(address spogRegistrar_) {
        if ((spogRegistrar = spogRegistrar_) == address(0)) revert ZeroSpogRegistrar();
    }

    function baseRate() public view returns (uint256 baseRate_) {
        return SPOGRegistrarReader.getBaseMinterRate(spogRegistrar);
    }

    function rate() external view returns (uint256 rate_) {
        return baseRate();
    }
}
