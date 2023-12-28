// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { SPOGRegistrarReader } from "./libs/SPOGRegistrarReader.sol";

import { IEarnerRateModel } from "./interfaces/IEarnerRateModel.sol";
import { IMToken } from "./interfaces/IMToken.sol";
import { IProtocol } from "./interfaces/IProtocol.sol";
import { ContinuousIndexingMath } from "./libs/ContinuousIndexingMath.sol";

import "forge-std/console.sol";

contract EarnerRateModel is IEarnerRateModel {
    uint256 internal constant _ONE = 10_000; // 100% in basis points.
    uint256 internal constant _RATE_CONFIDENCE_INTERVAL = 30 days;

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
        // rate2 = math.log((p1 * math.exp(rate1 * t) - p1 + p2) / p2) / t
        uint256 time_ = totalActiveOwedM_ > totalEarningSupply_ ? _RATE_CONFIDENCE_INTERVAL : 1;
        uint256 yearlyRate_ = ContinuousIndexingMath.convertFromBasisPoints(IProtocol(protocol).minterRate());
        uint256 exponent_ = ContinuousIndexingMath.exponent(
            uint72((uint256(yearlyRate_) * time_) / ContinuousIndexingMath.SECONDS_PER_YEAR)
        );
        // NOTE: Do not descale here, ln function expects 1e18
        uint256 lnArg_ = (totalActiveOwedM_ *
            exponent_ +
            totalEarningSupply_ *
            ContinuousIndexingMath.EXP_SCALED_ONE -
            totalActiveOwedM_ *
            ContinuousIndexingMath.EXP_SCALED_ONE) / totalEarningSupply_;

        uint256 safeRate_ = (uint256(_ln(int256(lnArg_ * 1e6))) * ContinuousIndexingMath.SECONDS_PER_YEAR) /
            time_ /
            1e14;
        // safeRate_ = (99 * safeRate_) / 100; // extra safety margin, it is needed for first X seconds after rate adjustment if totalEarningSupply > totalActiveOwedM

        // console.log("safe rate = ", safeRate_);
        // console.log("approx = ", (IProtocol(protocol).minterRate() * totalActiveOwedM_) / totalEarningSupply_);

        // safeRate_ = _min(safeRate_, (IProtocol(protocol).minterRate() * totalActiveOwedM_) / totalEarningSupply_);
        // uint256 safeRate_ = (IProtocol(protocol).minterRate() * totalActiveOwedM_) / totalEarningSupply_;

        return _min(baseRate(), safeRate_);
    }

    function baseRate() public view returns (uint256 baseRate_) {
        return SPOGRegistrarReader.getBaseEarnerRate(spogRegistrar);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ > b_ ? b_ : a_;
    }

    function _ln(int256 x) internal pure returns (int256 r) {
        unchecked {
            require(x > 0, "UNDEFINED");

            // We want to convert x from 10**18 fixed point to 2**96 fixed point.
            // We do this by multiplying by 2**96 / 10**18. But since
            // ln(x * C) = ln(x) + ln(C), we can simply do nothing here
            // and add ln(2**96 / 10**18) at the end.

            /// @solidity memory-safe-assembly
            assembly {
                r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
                r := or(r, shl(4, lt(0xffff, shr(r, x))))
                r := or(r, shl(3, lt(0xff, shr(r, x))))
                r := or(r, shl(2, lt(0xf, shr(r, x))))
                r := or(r, shl(1, lt(0x3, shr(r, x))))
                r := or(r, lt(0x1, shr(r, x)))
            }

            // Reduce range of x to (1, 2) * 2**96
            // ln(2^k * x) = k * ln(2) + ln(x)
            int256 k = r - 96;
            x <<= uint256(159 - k);
            x = int256(uint256(x) >> 159);

            // Evaluate using a (8, 8)-term rational approximation.
            // p is made monic, we will multiply by a scale factor later.
            int256 p = x + 3273285459638523848632254066296;
            p = ((p * x) >> 96) + 24828157081833163892658089445524;
            p = ((p * x) >> 96) + 43456485725739037958740375743393;
            p = ((p * x) >> 96) - 11111509109440967052023855526967;
            p = ((p * x) >> 96) - 45023709667254063763336534515857;
            p = ((p * x) >> 96) - 14706773417378608786704636184526;
            p = p * x - (795164235651350426258249787498 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            // q is monic by convention.
            int256 q = x + 5573035233440673466300451813936;
            q = ((q * x) >> 96) + 71694874799317883764090561454958;
            q = ((q * x) >> 96) + 283447036172924575727196451306956;
            q = ((q * x) >> 96) + 401686690394027663651624208769553;
            q = ((q * x) >> 96) + 204048457590392012362485061816622;
            q = ((q * x) >> 96) + 31853899698501571402653359427138;
            q = ((q * x) >> 96) + 909429971244387300277376558375;
            /// @solidity memory-safe-assembly
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial is known not to have zeros in the domain.
                // No scaling required because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r is in the range (0, 0.125) * 2**96

            // Finalization, we need to:
            // * multiply by the scale factor s = 5.549…
            // * add ln(2**96 / 10**18)
            // * add k * ln(2)
            // * multiply by 10**18 / 2**96 = 5**18 >> 78

            // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
            r *= 1677202110996718588342820967067443963516166;
            // add ln(2) * k * 5e18 * 2**192
            r += 16597577552685614221487285958193947469193820559219878177908093499208371 * k;
            // add ln(2**96 / 10**18) * 5e18 * 2**192
            r += 600920179829731861736702779321621459595472258049074101567377883020018308;
            // base conversion: mul 2**18 / 2**192
            r >>= 174;
        }
    }
}
