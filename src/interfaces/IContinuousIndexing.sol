// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

/**
 * @title  Continuous Indexing Interface.
 * @author M^0 Labs
 */
interface IContinuousIndexing {
    /* ============ Events ============ */

    /**
     * @notice Emitted when the index is updated.
     * @param  index The new index.
     */
    event IndexUpdated(uint128 indexed index);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Updates the latest index and latest accrual time in storage.
     * @param  index The new index to compute present amounts from principal amounts.
     */
    function updateIndex(uint128 index) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The current index that would be written to storage if `updateIndex` is called.
    function currentIndex() external view returns (uint128);

    /// @notice The latest updated index.
    function latestIndex() external view returns (uint128);

    /// @notice The latest timestamp when the index was updated.
    function latestUpdateTimestamp() external view returns (uint40);
}
