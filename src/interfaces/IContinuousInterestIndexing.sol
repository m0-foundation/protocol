// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IContinuousInterestIndexing {
    event IndexUpdated(uint256 indexed index);

    function currentIndex() external view returns (uint256 currentIndex);

    function latestAccrualTime() external view returns (uint256 latestAccrualTime);

    function latestIndex() external view returns (uint256 index);

    function updateIndex() external returns (uint256 currentIndex);
}
