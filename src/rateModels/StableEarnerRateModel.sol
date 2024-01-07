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
    uint32 internal constant _RATE_CONFIDENCE_INTERVAL = 30 days;

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

        // TODO: UIntMath.safe32
        return UIntMath.min256(baseRate(), ContinuousIndexingMath.convertToBasisPoints(uint32(safeEarnerRate_)));
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
    ) public pure returns (uint256) {
        // To ensure cashflow safety, we start with `cashFlowOfActiveOwedM == cashFlowOfEarningSupply` over any time.
        // Effectively: p1 * exp(rate1 * t) - p1 = p2 * exp(rate2 * t) - p2
        //          So: rate2 = ln(1 + (p1 * (exp(rate1 * t) - 1)) / p2) / t
        // 1. totalActive * d_minterIndex - totalActive == totalEarning * d_earnerIndex - totalEarning
        // 2. totalActive * (d_minterIndex - 1) == totalEarning * (d_earnerIndex - 1)
        // 3. totalActive * (d_minterIndex - 1) / totalEarning == d_earnerIndex - 1
        // 4. 1 + (totalActive * (d_minterIndex - 1) / totalEarning) = exponent((earnerRate * d) / SECONDS_PER_YEAR)
        // 5. ln(1 + (totalActive * (d_minterIndex - 1) / totalEarning)) = (earnerRate * d) / SECONDS_PER_YEAR
        // 6. ln(1 + (totalActive * (d_minterIndex - 1) / totalEarning)) * SECONDS_PER_YEAR / d = earnerRate

        if (totalActiveOwedM_ == 0) return 0;

        if (totalEarningSupply_ == 0) return type(uint256).max;

        uint48 deltaMinterIndex_ = ContinuousIndexingMath.getContinuousIndex(
            ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
            confidenceInterval_
        );

        uint256 lnArg_ = 1e12 +
            ((((totalActiveOwedM_ * (deltaMinterIndex_ - 1e12)) / 1e12) * 1e12) / totalEarningSupply_);

        uint256 lnResult_ = uint256(wadLn(int256(lnArg_ * 1e6)));

        return
            ContinuousIndexingMath.convertToBasisPoints(
                uint64(((lnResult_ / 1e6) * ContinuousIndexingMath.SECONDS_PER_YEAR) / confidenceInterval_)
            );
    }
}
