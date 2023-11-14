// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IInterestRateModel } from "./interfaces/IInterestRateModel.sol";
import { IContinuousInterestIndexing } from "./interfaces/IContinuousInterestIndexing.sol";

import { InterestMath } from "./libs/InterestMath.sol";

abstract contract ContinuousInterestIndexing is IContinuousInterestIndexing {
    // TODO: Consider packing these into a single slot.
    uint256 internal _latestIndex;
    uint256 internal _latestAccrualTime;

    constructor() {
        _latestIndex = 1 * InterestMath.EXP_BASE_SCALE;
        _latestAccrualTime = block.timestamp;
    }

    function updateIndex() public virtual returns (uint256 currentIndex_) {
        currentIndex_ = currentIndex();
        _latestIndex = currentIndex_;
        _latestAccrualTime = block.timestamp;

        emit IndexUpdated(currentIndex_);
    }

    function latestIndex() public view virtual returns (uint256 index_) {
        return _latestIndex;
    }

    function latestAccrualTime() public view virtual returns (uint256 latestAccrualTime_) {
        return _latestAccrualTime;
    }

    function currentIndex() public view virtual returns (uint256 currentIndex_) {
        return
            InterestMath.multiply(
                _latestIndex,
                InterestMath.getContinuousIndex(
                    InterestMath.convertFromBasisPoints(_rate()),
                    block.timestamp - _latestAccrualTime
                )
            );
    }

    function _getPrincipalAmountAndUpdateIndex(uint256 presentAmount_) internal returns (uint256 principalAmount_) {
        return _getPrincipalAmount(presentAmount_, updateIndex());
    }

    function _getPresentAmountAndUpdateIndex(uint256 principalAmount_) internal returns (uint256 presentAmount_) {
        return _getPresentAmount(principalAmount_, updateIndex());
    }

    function _rate() internal view virtual returns (uint256 rate_);

    function _getPrincipalAmount(
        uint256 presentAmount_,
        uint256 index_
    ) internal pure returns (uint256 principalAmount_) {
        return InterestMath.divide(presentAmount_, index_);
    }

    function _getPresentAmount(
        uint256 principalAmount_,
        uint256 index_
    ) internal pure returns (uint256 presentAmount_) {
        return InterestMath.multiply(principalAmount_, index_);
    }
}
