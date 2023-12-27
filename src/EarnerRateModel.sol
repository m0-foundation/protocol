// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";
import { UIntMath } from "./libs/UIntMath.sol";

import { IEarnerRateModel } from "./interfaces/IEarnerRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";

/**
 * @title Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^ZERO LABS_
 */
contract EarnerRateModel is IEarnerRateModel {
    /// @inheritdoc IEarnerRateModel
    address public immutable mToken;

    /// @inheritdoc IEarnerRateModel
    address public immutable protocol;

    /// @inheritdoc IEarnerRateModel
    address public immutable ttgRegistrar;

    /**
     * @notice Constructs the EarnerRateModel contract.
     * @param protocol_ The address of the protocol contract.
     */
    constructor(address protocol_) {
        if ((protocol = protocol_) == address(0)) revert ZeroProtocol();
        if ((ttgRegistrar = IProtocol(protocol_).ttgRegistrar()) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = IProtocol(protocol_).mToken()) == address(0)) revert ZeroMToken();
    }

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256) {
        uint256 totalActiveOwedM_ = IProtocol(protocol).totalActiveOwedM();

        if (totalActiveOwedM_ == 0) return 0;

        uint256 totalEarningSupply_ = IMToken(mToken).totalEarningSupply();

        if (totalEarningSupply_ == 0) return baseRate();

        // NOTE: Calculate safety guard rate that prevents overprinting of M.
        // TODO: Discuss the pros/cons of moving this into M Token after all integration/invariants tests are done.
        return
            UIntMath.min256(baseRate(), (IProtocol(protocol).minterRate() * totalActiveOwedM_) / totalEarningSupply_);
    }

    /// @inheritdoc IEarnerRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return TTGRegistrarReader.getBaseEarnerRate(ttgRegistrar);
    }
}
