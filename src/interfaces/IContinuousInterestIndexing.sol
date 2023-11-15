// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

interface IContinuousInterestIndexing {
    event IndexUpdated(uint256 indexed index);

    /**
     * @notice The current index that would be written to storage if `updateIndex` is called.
     */
    function currentIndex() external view returns (uint256 currentIndex);

    /**
     * @notice The latest timestamp when the index was updated.
     */
    function latestAccrualTime() external view returns (uint256 latestAccrualTime);

    /**
     * @notice The latest updated index.
     */
    function latestIndex() external view returns (uint256 index);

    /**
     * @notice Updates the latest index and latest accrual time in storage.
     * @return index The new stored index for computing present values from principal values.
     */
    function updateIndex() external returns (uint256 index);
}
