// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "./IRateModel.sol";

interface IMinterRateModel is IRateModel {
    error ZeroSpogRegistrar();

    function spogRegistrar() external view returns (address);

    function baseRate() external view returns (uint256);
}
