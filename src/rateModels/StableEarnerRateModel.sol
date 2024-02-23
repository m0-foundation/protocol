// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { wadLn } from "../../lib/solmate/src/utils/SignedWadMath.sol";
import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { ContinuousIndexingMath } from "../libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../libs/TTGRegistrarReader.sol";

import { IMToken } from "../interfaces/IMToken.sol";
import { IMinterGateway } from "../interfaces/IMinterGateway.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";

import { IEarnerRateModel } from "./interfaces/IEarnerRateModel.sol";
import { IStableEarnerRateModel } from "./interfaces/IStableEarnerRateModel.sol";

/**
 * @title  Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^0 Labs
 */
contract StableEarnerRateModel is IStableEarnerRateModel {
    /// @inheritdoc IStableEarnerRateModel
    uint32 public constant RATE_CONFIDENCE_INTERVAL = 30 days;

    /// @inheritdoc IStableEarnerRateModel
    uint32 public constant EARNER_SPLIT_MULTIPLIER = 9_000; // 90% in basis points.

    /// @inheritdoc IStableEarnerRateModel
    uint32 public constant ONE = 10_000; // 100% in basis points.

    /// @notice The scaling of rates in for exponent math.
    uint256 internal constant EXP_SCALED_ONE = 1e12;

    /// @notice The scaling of `EXP_SCALED_ONE` for wad maths operations.
    int256 internal constant WAD_TO_EXP_SCALER = 1e6;

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
        uint256 safeEarnerRate_ = getSafeEarnerRate(
            IMinterGateway(minterGateway).totalActiveOwedM(),
            IMToken(mToken).totalEarningSupply(),
            IMinterGateway(minterGateway).minterRate(),
            RATE_CONFIDENCE_INTERVAL
        );

        return UIntMath.min256(baseRate(), (EARNER_SPLIT_MULTIPLIER * safeEarnerRate_) / ONE);
    }

    /// @inheritdoc IEarnerRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return TTGRegistrarReader.getBaseEarnerRate(ttgRegistrar);
    }

    /// @inheritdoc IStableEarnerRateModel
    function getSafeEarnerRate(
        uint240 totalActiveOwedM_,
        uint240 totalEarningSupply_,
        uint32 minterRate_,
        uint32 confidenceInterval_
    ) public pure returns (uint32) {
        if (totalActiveOwedM_ == 0) return 0;

        if (totalEarningSupply_ == 0) return type(uint32).max;

        if (totalActiveOwedM_ == totalEarningSupply_) return minterRate_;

        return
            totalActiveOwedM_ > totalEarningSupply_
                ? _getStableRate(totalActiveOwedM_, totalEarningSupply_, minterRate_, confidenceInterval_)
                : _getApproxRate(totalActiveOwedM_, totalEarningSupply_, minterRate_);
    }

    function _getStableRate(
        uint240 totalActiveOwedM_,
        uint240 totalEarningSupply_,
        uint32 minterRate_,
        uint32 confidenceInterval_
    ) internal pure returns (uint32) {
        // To ensure cashflow safety, we start with `cashFlowOfActiveOwedM == cashFlowOfEarningSupply` over some time.
        // Effectively: p1 * exp(rate1 * dt) - p1 = p2 * exp(rate2 * dt) - p2
        //          So: rate2 = ln(1 + (p1 * (exp(rate1 * dt) - 1)) / p2) / dt
        // 1. totalActive * delta_minterIndex - totalActive == totalEarning * delta_earnerIndex - totalEarning
        // 2. totalActive * (delta_minterIndex - 1) == totalEarning * (delta_earnerIndex - 1)
        // 3. totalActive * (delta_minterIndex - 1) / totalEarning == delta_earnerIndex - 1
        // Substitute `delta_earnerIndex` with `exponent((earnerRate * dt) / SECONDS_PER_YEAR)`:
        // 4. 1 + (totalActive * (delta_minterIndex - 1) / totalEarning) = exponent((earnerRate * dt) / SECONDS_PER_YEAR)
        // 5. ln(1 + (totalActive * (delta_minterIndex - 1) / totalEarning)) = (earnerRate * dt) / SECONDS_PER_YEAR
        // 6. ln(1 + (totalActive * (delta_minterIndex - 1) / totalEarning)) * SECONDS_PER_YEAR / dt = earnerRate

        if (confidenceInterval_ == 0) return 0;

        uint48 deltaMinterIndex_ = ContinuousIndexingMath.getContinuousIndex(
            ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
            confidenceInterval_
        );

        int256 lnArg_ = int256(
            EXP_SCALED_ONE + ((uint256(totalActiveOwedM_) * (deltaMinterIndex_ - EXP_SCALED_ONE)) / totalEarningSupply_)
        );

        int256 lnResult_ = wadLn(lnArg_ * WAD_TO_EXP_SCALER) / WAD_TO_EXP_SCALER;

        uint256 expRate_ = (uint256(lnResult_) * ContinuousIndexingMath.SECONDS_PER_YEAR) / confidenceInterval_;

        if (expRate_ > type(uint64).max) return type(uint32).max;

        // NOTE: Do not need to do `UIntMath.safe256` because it is known that `lnResult_` will not be negative.
        uint40 safeRate_ = ContinuousIndexingMath.convertToBasisPoints(uint64(expRate_));

        return (safeRate_ > type(uint32).max) ? type(uint32).max : uint32(safeRate_);
    }

    function _getApproxRate(
        uint240 totalActiveOwedM_,
        uint240 totalEarningSupply_,
        uint32 minterRate_
    ) internal pure returns (uint32) {
        // To ensure cashflow safety, we start with `cashFlowOfActiveOwedM == cashFlowOfEarningSupply` over some time.
        // We use approximation: p1 * rate1 = p2 * rate2
        //                   So: rate2 = p1 * rate1 / p2

        uint256 safeRate_ = (totalActiveOwedM_ * minterRate_) / totalEarningSupply_;

        return (safeRate_ > type(uint32).max) ? type(uint32).max : uint32(safeRate_);
    }
}
