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

/**
 * @title  Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^0 Labs
 */
contract StableEarnerRateModel is IEarnerRateModel {
    // TODO: Can be a TTG Registrar parameter.
    uint32 internal constant _RATE_CONFIDENCE_INTERVAL = 30 days;

    // TODO: Can be a TTG Registrar parameter.
    uint32 internal constant _EXTRA_SAFETY_MULTIPLIER = 9_500; // 95 % in basis points

    uint32 internal constant _ONE = 10_000; // 100 % in basis points

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
            _RATE_CONFIDENCE_INTERVAL
        );

        return UIntMath.min256(baseRate(), (_EXTRA_SAFETY_MULTIPLIER * safeEarnerRate_) / _ONE);
    }

    /// @inheritdoc IEarnerRateModel
    function baseRate() public view returns (uint256 baseRate_) {
        return TTGRegistrarReader.getBaseEarnerRate(ttgRegistrar);
    }

    function getSafeEarnerRate(
        uint240 totalActiveOwedM_,
        uint240 totalEarningSupply_,
        uint32 minterRate_,
        uint32 confidenceInterval_
    ) public pure returns (uint32) {
        // To ensure cashflow safety, we start with `cashFlowOfActiveOwedM == cashFlowOfEarningSupply` over some time.
        // Effectively: p1 * exp(rate1 * dt) - p1 = p2 * exp(rate2 * dt) - p2
        //          So: rate2 = ln(1 + (p1 * (exp(rate1 * dt) - 1)) / p2) / dt
        // 1. totalActive * d_minterIndex - totalActive == totalEarning * d_earnerIndex - totalEarning
        // 2. totalActive * (d_minterIndex - 1) == totalEarning * (d_earnerIndex - 1)
        // 3. totalActive * (d_minterIndex - 1) / totalEarning == d_earnerIndex - 1
        // Substitute `d_earnerIndex` with `exponent((earnerRate * dt) / SECONDS_PER_YEAR)`:
        // 4. 1 + (totalActive * (d_minterIndex - 1) / totalEarning) = exponent((earnerRate * dt) / SECONDS_PER_YEAR)
        // 5. ln(1 + (totalActive * (d_minterIndex - 1) / totalEarning)) = (earnerRate * dt) / SECONDS_PER_YEAR
        // 6. ln(1 + (totalActive * (d_minterIndex - 1) / totalEarning)) * SECONDS_PER_YEAR / dt = earnerRate

        if (totalActiveOwedM_ == 0) return 0;

        if (totalEarningSupply_ == 0) return type(uint32).max;

        uint48 deltaMinterIndex_ = ContinuousIndexingMath.getContinuousIndex(
            ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
            confidenceInterval_
        );

        // NOTE: 1e12 is `EXP_ONE` in ContinuousIndexingMath. 1e18 is `WAD_ONE` in SignedWadMath.
        int256 lnArg_ = int256(
            1e12 + ((((uint256(totalActiveOwedM_) * (deltaMinterIndex_ - 1e12)) / 1e12) * 1e12) / totalEarningSupply_)
        );

        int256 lnResult_ = wadLn(lnArg_ * 1e6) / 1e6; // Scale/Descale by 1e6 for SignedWadMath.

        // TODO: UIntMath.safe256 and/or UIntMath.safe64?
        return
            ContinuousIndexingMath.convertToBasisPoints(
                uint64((uint256(lnResult_) * ContinuousIndexingMath.SECONDS_PER_YEAR) / confidenceInterval_)
            );
    }
}
