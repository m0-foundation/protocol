// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexing } from "../../../src/ContinuousIndexing.sol";

contract ContinuousIndexingHarness is ContinuousIndexing {
    uint256 internal _mockRate = 0;

    function setter_rate(uint256 mockRate_) external {
        _mockRate = mockRate_;
    }

    function getter_rate() external view returns (uint256) {
        return _mockRate;
    }

    function setter_latestIndex(uint256 latestIndex_) external {
        _latestIndex = latestIndex_;
    }

    function setter_latestRate(uint256 latestRate_) external {
        _latestRate = latestRate_;
    }

    function setter_latestUpdateTimestamp(uint256 latestUpdateTimestamp_) external {
        _latestUpdateTimestamp = latestUpdateTimestamp_;
    }

    function external_getPresentAmountAndUpdateIndex(uint256 principalAmount_) external returns (uint256) {
        return _getPresentAmountAndUpdateIndex(principalAmount_);
    }

    function external_getPrincipalAmountAndUpdateIndex(uint256 presentAmount_) external returns (uint256) {
        return _getPrincipalAmount(presentAmount_, updateIndex());
    }

    function external_getPresentAmount(uint256 principalAmount_, uint256 index_) external pure returns (uint256) {
        return _getPresentAmount(principalAmount_, index_);
    }

    function external_getPrincipalAmount(uint256 presentAmount_, uint256 index_) external pure returns (uint256) {
        return _getPresentAmount(presentAmount_, index_);
    }

    function external_updateIndex() external virtual returns (uint256) {
        return updateIndex();
    }

    function external_rate() external view virtual returns (uint256 rate_) {
        return _rate();
    }

    function _rate() internal view override returns (uint256 rate_) {
        return _mockRate;
    }
}
