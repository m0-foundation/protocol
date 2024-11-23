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

    /* ============ Custom Error ============ */

    /**
     * @notice Emitted during index update when the new index is less than the current one.
     * @param  index The new index.
     * @param  currentIndex The current index.
     */
    error DecreasingIndex(uint128 index, uint128 currentIndex);

    /* ============ View/Pure Functions ============ */

    /// @notice The current index that was last written to storage when `updatedIndex` was called.
    function currentIndex() external view returns (uint128);

    /// @notice The latest updated index.
    function latestIndex() external view returns (uint128);

    /// @notice The latest timestamp when the index was updated.
    function latestUpdateTimestamp() external view returns (uint40);
}
