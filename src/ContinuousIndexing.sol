// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { IContinuousIndexing } from "./interfaces/IContinuousIndexing.sol";
import { IRateModel } from "./interfaces/IRateModel.sol";

import { ContinuousIndexingMath } from "./libs/ContinuousIndexingMath.sol";

abstract contract ContinuousIndexing is IContinuousIndexing {
    // TODO: Consider packing these into a single slot.
    uint256 internal _latestIndex;
    uint256 internal _latestUpdateTimestamp;

    constructor() {
        _latestIndex = 1 * ContinuousIndexingMath.EXP_BASE_SCALE;
        _latestUpdateTimestamp = block.timestamp;
    }

    function updateIndex() public virtual returns (uint256 currentIndex_) {
        if (_latestUpdateTimestamp == block.timestamp) return _latestIndex;

        currentIndex_ = currentIndex();
        _latestIndex = currentIndex_;
        _latestUpdateTimestamp = block.timestamp;

        emit IndexUpdated(currentIndex_);
    }

    function latestIndex() public view virtual returns (uint256 index_) {
        return _latestIndex;
    }

    function latestUpdateTimestamp() public view virtual returns (uint256 latestAccrualTime_) {
        return _latestUpdateTimestamp;
    }

    function currentIndex() public view virtual returns (uint256 currentIndex_) {
        return
            ContinuousIndexingMath.multiply(
                _latestIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(_rate()),
                    block.timestamp - _latestUpdateTimestamp
                )
            );
    }

    function _getPresentAmountAndUpdateIndex(uint256 principalAmount_) internal returns (uint256 presentAmount_) {
        return _getPresentAmount(principalAmount_, updateIndex());
    }

    function _getPrincipalAmountAndUpdateIndex(uint256 presentAmount_) internal returns (uint256 principalAmount_) {
        return _getPrincipalAmount(presentAmount_, updateIndex());
    }

    function _rate() internal view virtual returns (uint256 rate_);

    function _getPresentAmount(
        uint256 principalAmount_,
        uint256 index_
    ) internal pure returns (uint256 presentAmount_) {
        return ContinuousIndexingMath.multiply(principalAmount_, index_);
    }

    function _getPrincipalAmount(
        uint256 presentAmount_,
        uint256 index_
    ) internal pure returns (uint256 principalAmount_) {
        return ContinuousIndexingMath.divide(presentAmount_, index_);
    }
}
