// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IEarnerRateModel } from "./interfaces/IEarnerRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";

contract EarnerRateModel is IEarnerRateModel {
    uint256 internal constant _ONE = 10_000; // 100% in basis points.

    address public immutable mToken;
    address public immutable protocol;
    address public immutable spogRegistrar;

    constructor(address protocol_) {
        if ((protocol = protocol_) == address(0)) revert ZeroProtocol();
        if ((spogRegistrar = IProtocol(protocol_).spogRegistrar()) == address(0)) revert ZeroSpogRegistrar();
        if ((mToken = IProtocol(protocol_).mToken()) == address(0)) revert ZeroMToken();
    }

    function rate() external view returns (uint256 rate_) {
        uint256 totalActiveOwedM_ = IProtocol(protocol).totalActiveOwedM();

        if (totalActiveOwedM_ == 0) return 0;

        uint256 totalEarningSupply_ = IMToken(mToken).totalEarningSupply();

        if (totalEarningSupply_ == 0) return baseRate();

        // NOTE: Calculate safety guard rate that prevents overprinting of M.
        // TODO: Move this into M Token itself after all integration/invariants tests are done.
        uint256 safeRate_ = (IProtocol(protocol).minterRate() * totalActiveOwedM_) / totalEarningSupply_;

        return _min(baseRate(), safeRate_);
    }

    function baseRate() public view returns (uint256 baseRate_) {
        return SPOGRegistrarReader.getBaseEarnerRate(spogRegistrar);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? b_ : a_;
    }
}
