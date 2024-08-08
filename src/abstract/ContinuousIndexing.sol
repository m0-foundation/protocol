// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IContinuousIndexing } from "../interfaces/IContinuousIndexing.sol";

import { ContinuousIndexingMath } from "../libs/ContinuousIndexingMath.sol";

/**
 * @title Abstract Continuous Indexing Contract to handle index updates in inheriting contracts.
 * @author M^0 Labs
 */
abstract contract ContinuousIndexing is IContinuousIndexing {
    /* ============ Variables ============ */

    /// @inheritdoc IContinuousIndexing
    uint128 public latestIndex;

    /// @inheritdoc IContinuousIndexing
    uint40 public latestUpdateTimestamp;

    /* ============ Constructor ============ */

    /// @notice Constructs the ContinuousIndexing contract.
    constructor() {
        latestIndex = ContinuousIndexingMath.EXP_SCALED_ONE;
        latestUpdateTimestamp = uint40(block.timestamp);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IContinuousIndexing
    function updateIndex(uint128 index_) public virtual {
        if (index_ <= latestIndex) return;

        latestIndex = index_;
        latestUpdateTimestamp = uint40(block.timestamp);

        emit IndexUpdated(index_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IContinuousIndexing
    function currentIndex() public view virtual returns (uint128);

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the principal amount (rounded down) given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_) internal view returns (uint112) {
        return _getPrincipalAmountRoundedDown(presentAmount_, currentIndex());
    }

    /**
     * @dev    Returns the principal amount (rounded up) given the present amount and an index.
     * @param  presentAmount_ The present amount.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint240 presentAmount_) internal view returns (uint112) {
        return _getPrincipalAmountRoundedUp(presentAmount_, currentIndex());
    }

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }

    /**
     * @dev    Returns the present amount (rounded up) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded up.
     */
    function _getPresentAmountRoundedUp(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyUp(principalAmount_, index_);
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @param  index_         An index.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return ContinuousIndexingMath.divideDown(presentAmount_, index_);
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @param  index_         An index.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return ContinuousIndexingMath.divideUp(presentAmount_, index_);
    }
}
