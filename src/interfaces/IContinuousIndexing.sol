// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

/// @title Continuous Indexing Interface.
interface IContinuousIndexing {
    event IndexUpdated(uint128 indexed index, uint32 indexed rate);

    /// @notice The current index that would be written to storage if `updateIndex` is called.
    function currentIndex() external view returns (uint128);

    /// @notice The latest updated index.
    function latestIndex() external view returns (uint128);

    /// @notice The latest timestamp when the index was updated.
    function latestUpdateTimestamp() external view returns (uint40);

    /**
     * @notice Updates the latest index and latest accrual time in storage.
     * @return index The new stored index for computing present amounts from principal amounts.
     */
    function updateIndex() external returns (uint128);
}
