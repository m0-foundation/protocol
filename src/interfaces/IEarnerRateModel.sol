// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IRateModel } from "./IRateModel.sol";

interface IEarnerRateModel is IRateModel {
    error ZeroMToken();

    error ZeroProtocol();

    error ZeroSpogRegistrar();

    function mToken() external view returns (address);

    function protocol() external view returns (address);

    function spogRegistrar() external view returns (address);

    function baseRate() external view returns (uint256);
}
