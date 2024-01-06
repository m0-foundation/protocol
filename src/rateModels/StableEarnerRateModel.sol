// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { wadLn } from "../../lib/solmate/src/utils/SignedWadMath.sol";

import { TTGRegistrarReader } from "../libs/TTGRegistrarReader.sol";
import { UIntMath } from "../libs/UIntMath.sol";

import { IEarnerRateModel } from "../interfaces/rateModels/IEarnerRateModel.sol";
import { IMToken } from "../interfaces/IMToken.sol";
import { IMinterGateway } from "../interfaces/IMinterGateway.sol";
import { IRateModel } from "../interfaces/rateModels/IRateModel.sol";
import { ContinuousIndexingMath } from "../libs/ContinuousIndexingMath.sol";

/**
 * @title Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^0 Labs
 */
contract StableEarnerRateModel is IEarnerRateModel {
    uint256 internal constant _RATE_CONFIDENCE_INTERVAL = 30 days;

    /// @inheritdoc IEarnerRateModel
    address public immutable mToken;

    /// @inheritdoc IEarnerRateModel
    address public immutable minterGateway;

    /// @inheritdoc IEarnerRateModel
    address public immutable ttgRegistrar;

    /**
     * @notice Constructs the EarnerRateModel contract.
     * @param minterGateway_ The address of the Minter Gateway contract.
     */
    constructor(address minterGateway_) {
        if ((minterGateway = minterGateway_) == address(0)) revert ZeroMinterGateway();
        if ((ttgRegistrar = IMinterGateway(minterGateway_).ttgRegistrar()) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = IMinterGateway(minterGateway_).mToken()) == address(0)) revert ZeroMToken();
    }

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256) {
        uint256 totalActiveOwedM_ = IMinterGateway(minterGateway).totalActiveOwedM();

        if (totalActiveOwedM_ == 0) return 0;

        uint256 totalEarningSupply_ = IMToken(mToken).totalEarningSupply();

        if (totalEarningSupply_ == 0) return baseRate();

        // NOTE: Calculate safety guard rate that prevents overprinting of M.
        // p1 * exp(rate1 * t) - p1 = p2 * exp(rate2 * t) - p2
        uint256 time_ = totalActiveOwedM_ > totalEarningSupply_ ? _RATE_CONFIDENCE_INTERVAL : 1;
        uint256 exponent_ = ContinuousIndexingMath.exponent(
            uint72(
                (uint256(ContinuousIndexingMath.convertFromBasisPoints(IMinterGateway(minterGateway).minterRate())) *
                    time_) / ContinuousIndexingMath.SECONDS_PER_YEAR
            )
        );

        // NOTE: Scale up argument in `EXP_BASE_SCALE` to 1e18 wad.
        // rate2 = ln(1 + (p1 * exp(rate1 * t) - p1) / p2) / t
        uint256 wadLnArg_ = (1e18 +
            (1e6 * (totalActiveOwedM_ * (exponent_ - ContinuousIndexingMath.EXP_SCALED_ONE))) /
            totalEarningSupply_);
        uint256 wadLnRes_ = uint256(wadLn(int256(wadLnArg_)));
        uint256 safeRate_ = (wadLnRes_ * ContinuousIndexingMath.SECONDS_PER_YEAR) / time_ / 1e14;

        return UIntMath.min256(baseRate(), safeRate_);
    }

    /// @inheritdoc IEarnerRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return TTGRegistrarReader.getBaseEarnerRate(ttgRegistrar);
    }
}
