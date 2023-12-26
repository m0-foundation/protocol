// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IContinuousIndexing } from "../interfaces/IContinuousIndexing.sol";

import { ContinuousIndexingMath } from "../libs/ContinuousIndexingMath.sol";

/**
 * @title Abstract Continuous Indexing Contract to handle rate/index updates in inheriting contracts.
 * @author M^ZERO LABS_
 */
abstract contract ContinuousIndexing is IContinuousIndexing {
    /// @dev The latest updated index.
    uint128 internal _latestIndex;

    /// @dev The latest updated rate.
    uint32 internal _latestRate;

    /// @dev The latest timestamp when the index was updated.
    uint40 internal _latestUpdateTimestamp;

    /// @notice Constructs the ContinuousIndexing contract.
    constructor() {
        _latestIndex = uint128(1 * ContinuousIndexingMath.EXP_SCALED_ONE);
        _latestUpdateTimestamp = uint40(block.timestamp);
    }

    /******************************************************************************************************************\
    |                                      External/Public Interactive Functions                                       |
    \******************************************************************************************************************/

    /// @inheritdoc IContinuousIndexing
    function updateIndex() public virtual returns (uint128 currentIndex_) {
        // NOTE: `_rate()` can depend indirectly on `_latestIndex` and `_latestUpdateTimestamp`, if the RateModel
        //       depends on earning balances/supply, which depends on `currentIndex()`, so only update them after this.
        uint32 rate_ = _rate();

        if (_latestUpdateTimestamp == block.timestamp && _latestRate == rate_) return _latestIndex;

        // NOTE: `currentIndex()` depends on `_latestRate`, so only update it after this.
        _latestIndex = currentIndex_ = currentIndex();
        _latestRate = rate_;
        _latestUpdateTimestamp = uint40(block.timestamp);

        emit IndexUpdated(currentIndex_, rate_);
    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    /// @inheritdoc IContinuousIndexing
    function currentIndex() public view virtual returns (uint128) {
        uint32 time_;

        // NOTE: safe to use unchecked here, since `block.timestamp` is always greater than `_latestUpdateTimestamp`.
        unchecked {
            time_ = uint32(block.timestamp - _latestUpdateTimestamp);
        }

        // NOTE: While `multiplyUp` can mostly result in additional continuous compounding accuracy (mainly because Padé
        //       exponent approximations always results in a lower value, and `multiplyUp` artificially increases that
        //       value), for some smaller `r*t` values, it results in a higher effective index than the "ideal". While
        //       not really an issue, this "often lower than, but sometimes higher than, ideal index" may no be a good
        //       characteristic, and `multiplyUp` does costs a tiny bit more gas.
        return
            ContinuousIndexingMath.multiplyDown(
                _latestIndex,
                ContinuousIndexingMath.getContinuousIndex(
                    ContinuousIndexingMath.convertFromBasisPoints(_latestRate),
                    time_
                )
            );
    }

    /// @inheritdoc IContinuousIndexing
    function latestIndex() public view virtual returns (uint128) {
        return _latestIndex;
    }

    /// @inheritdoc IContinuousIndexing
    function latestUpdateTimestamp() public view virtual returns (uint40) {
        return _latestUpdateTimestamp;
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint128 principalAmount_, uint128 index_) internal pure returns (uint128) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }

    /**
     * @dev    Returns the present amount (rounded up) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded up.
     */
    function _getPresentAmountRoundedUp(uint128 principalAmount_, uint128 index_) internal pure returns (uint128) {
        return ContinuousIndexingMath.multiplyUp(principalAmount_, index_);
    }

    /**
     * @dev    Returns the principal amount (rounded down) given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint128 presentAmount_) internal view returns (uint128) {
        return _getPrincipalAmountRoundedDown(presentAmount_, currentIndex());
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @param  index_         An index.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmountRoundedDown(uint128 presentAmount_, uint128 index_) internal pure returns (uint128) {
        return ContinuousIndexingMath.divideDown(presentAmount_, index_);
    }

    /**
     * @dev    Returns the principal amount (rounded up) given the present amount and an index.
     * @param  presentAmount_ The present amount.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint128 presentAmount_) internal view returns (uint128) {
        return _getPrincipalAmountRoundedUp(presentAmount_, currentIndex());
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @param  index_         An index.
     * @return The principal amount rounded up.
     */
    function _getPrincipalAmountRoundedUp(uint128 presentAmount_, uint128 index_) internal pure returns (uint128) {
        return ContinuousIndexingMath.divideUp(presentAmount_, index_);
    }

    /// @dev Overriden in the inheriting contract to return the current rate.
    function _rate() internal view virtual returns (uint32);
}
