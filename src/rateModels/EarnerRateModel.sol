// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { wadLn } from "../../lib/solmate/src/utils/SignedWadMath.sol";
import { UIntMath } from "../../lib/common/src/libs/UIntMath.sol";

import { ContinuousIndexingMath } from "../libs/ContinuousIndexingMath.sol";

import { IMToken } from "../interfaces/IMToken.sol";
import { IMinterGateway } from "../interfaces/IMinterGateway.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { ITTGRegistrar } from "../interfaces/ITTGRegistrar.sol";

import { IEarnerRateModel } from "./interfaces/IEarnerRateModel.sol";

/**
 * @title  Earner Rate Model contract set in TTG (Two Token Governance) Registrar and accessed by MToken.
 * @author M^0 Labs
 */
contract EarnerRateModel is IEarnerRateModel {
    /* ============ Variables ============ */

    /// @inheritdoc IEarnerRateModel
    uint32 public constant RATE_CONFIDENCE_INTERVAL = 30 days;

    /// @inheritdoc IEarnerRateModel
    uint32 public constant RATE_MULTIPLIER = 9_000; // 90% in basis points.

    /// @inheritdoc IEarnerRateModel
    uint32 public constant ONE = 10_000; // 100% in basis points.

    /// @notice The name of parameter in TTG that defines the max earner rate.
    bytes32 internal constant _MAX_EARNER_RATE = "max_earner_rate";

    /// @notice The scaling of rates in for exponent math.
    uint256 internal constant _EXP_SCALED_ONE = 1e12;

    /// @notice The scaling of `_EXP_SCALED_ONE` for wad maths operations.
    int256 internal constant _WAD_TO_EXP_SCALER = 1e6;

    /// @inheritdoc IEarnerRateModel
    address public immutable mToken;

    /// @inheritdoc IEarnerRateModel
    address public immutable minterGateway;

    /// @inheritdoc IEarnerRateModel
    address public immutable ttgRegistrar;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the EarnerRateModel contract.
     * @param minterGateway_ The address of the Minter Gateway contract.
     */
    constructor(address minterGateway_) {
        if ((minterGateway = minterGateway_) == address(0)) revert ZeroMinterGateway();
        if ((ttgRegistrar = IMinterGateway(minterGateway_).ttgRegistrar()) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = IMinterGateway(minterGateway_).mToken()) == address(0)) revert ZeroMToken();
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IRateModel
    function rate() external view returns (uint256) {
        uint256 safeEarnerRate_ = getSafeEarnerRate(
            IMinterGateway(minterGateway).totalActiveOwedM(),
            IMToken(mToken).totalEarningSupply(),
            IMinterGateway(minterGateway).minterRate()
        );

        return UIntMath.min256(maxRate(), (RATE_MULTIPLIER * safeEarnerRate_) / ONE);
    }

    /// @inheritdoc IEarnerRateModel
    function maxRate() public view returns (uint256) {
        return uint256(ITTGRegistrar(ttgRegistrar).get(_MAX_EARNER_RATE));
    }

    /// @inheritdoc IEarnerRateModel
    function getSafeEarnerRate(
        uint240 totalActiveOwedM_,
        uint240 totalEarningSupply_,
        uint32 minterRate_
    ) public pure returns (uint32) {
        // solhint-disable max-line-length
        // When `totalActiveOwedM_ >= totalEarningSupply_`, it is possible for the earner rate to be higher than the
        // minter rate and still ensure cashflow safety over some period of time (`RATE_CONFIDENCE_INTERVAL`). To ensure
        // cashflow safety, we start with `cashFlowOfActiveOwedM >= cashFlowOfEarningSupply` over some time `dt`.
        // Effectively: p1 * (exp(rate1 * dt) - 1) >= p2 * (exp(rate2 * dt) - 1)
        //          So: rate2 <= ln(1 + (p1 * (exp(rate1 * dt) - 1)) / p2) / dt
        // 1. totalActive * (delta_minterIndex - 1) >= totalEarning * (delta_earnerIndex - 1)
        // 2. totalActive * (delta_minterIndex - 1) / totalEarning >= delta_earnerIndex - 1
        // 3. 1 + (totalActive * (delta_minterIndex - 1) / totalEarning) >= delta_earnerIndex
        // Substitute `delta_earnerIndex` with `exponent((earnerRate * dt) / SECONDS_PER_YEAR)`:
        // 4. 1 + (totalActive * (delta_minterIndex - 1) / totalEarning) >= exponent((earnerRate * dt) / SECONDS_PER_YEAR)
        // 5. ln(1 + (totalActive * (delta_minterIndex - 1) / totalEarning)) >= (earnerRate * dt) / SECONDS_PER_YEAR
        // 6. ln(1 + (totalActive * (delta_minterIndex - 1) / totalEarning)) * SECONDS_PER_YEAR / dt >= earnerRate

        // When `totalActiveOwedM_ <= totalEarningSupply_`, the instantaneous earner cash flow must be less than the
        // instantaneous minter cash flow. To ensure instantaneous cashflow safety, we we use the derivatives of the
        // previous starting inequality, and substitute `dt = 0`.
        // Effectively: p1 * rate1 >= p2 * rate2
        //          So: rate2 <= p1 * rate1 / p2
        // 1. totalActive * minterRate >= totalEarning * earnerRate
        // 2. totalActive * minterRate / totalEarning >= earnerRate
        // solhint-enable max-line-length

        if (totalActiveOwedM_ == 0 || minterRate_ == 0) return 0;

        if (totalEarningSupply_ == 0) return type(uint32).max;

        if (totalActiveOwedM_ <= totalEarningSupply_) {
            // NOTE: `totalActiveOwedM_ * minterRate_` can revert due to overflow, so in some distant future, a new
            //       rate model contract may be needed that handles this differently.
            return uint32((uint256(totalActiveOwedM_) * minterRate_) / totalEarningSupply_);
        }

        uint48 deltaMinterIndex_ = ContinuousIndexingMath.getContinuousIndex(
            ContinuousIndexingMath.convertFromBasisPoints(minterRate_),
            RATE_CONFIDENCE_INTERVAL
        );

        // NOTE: `totalActiveOwedM_ * deltaMinterIndex_` can revert due to overflow, so in some distant future, a new
        //       rate model contract may be needed that handles this differently.
        int256 lnArg_ = int256(
            _EXP_SCALED_ONE +
                ((uint256(totalActiveOwedM_) * (deltaMinterIndex_ - _EXP_SCALED_ONE)) / totalEarningSupply_)
        );

        int256 lnResult_ = wadLn(lnArg_ * _WAD_TO_EXP_SCALER) / _WAD_TO_EXP_SCALER;

        uint256 expRate_ = (uint256(lnResult_) * ContinuousIndexingMath.SECONDS_PER_YEAR) / RATE_CONFIDENCE_INTERVAL;

        if (expRate_ > type(uint64).max) return type(uint32).max;

        // NOTE: Do not need to do `UIntMath.safe256` because it is known that `lnResult_` will not be negative.
        uint40 safeRate_ = ContinuousIndexingMath.convertToBasisPoints(uint64(expRate_));

        return (safeRate_ > type(uint32).max) ? type(uint32).max : uint32(safeRate_);
    }
}
