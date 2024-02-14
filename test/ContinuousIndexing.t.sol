// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";

import { ContinuousIndexingHarness } from "./utils/ContinuousIndexingHarness.sol";
import { TestUtils } from "./utils/TestUtils.sol";

contract ContinuousIndexingTests is TestUtils {
    ContinuousIndexingHarness internal _continuousIndexing;
    uint32 internal _rate;

    function setUp() external {
        _continuousIndexing = new ContinuousIndexingHarness();
        _rate = _continuousIndexing.rate();
    }

    /* ============ constructor ============ */
    function test_constructor() external {
        assertEq(_continuousIndexing.latestIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);
        assertEq(_continuousIndexing.latestUpdateTimestamp(), block.timestamp);
    }

    /* ============ currentIndex ============ */
    function test_currentIndex_timestampOverflow() external {
        assertEq(_continuousIndexing.updateIndex(), ContinuousIndexingMath.EXP_SCALED_ONE);

        vm.warp(block.timestamp + type(uint24).max);

        uint128 prevIndex_ = _continuousIndexing.updateIndex();
        assertEq(prevIndex_, _getContinuousIndexAt(_rate, ContinuousIndexingMath.EXP_SCALED_ONE, type(uint24).max));

        vm.warp(block.timestamp + type(uint32).max);

        // We haven't overflowed uint32 yet, so the index should still be computed properly.
        assertEq(_continuousIndexing.currentIndex(), _getContinuousIndexAt(_rate, prevIndex_, type(uint32).max));

        vm.warp(block.timestamp + 1);

        // We've now overflowed uint32, so it should return the last recorded index at `block.timestamp + type(uint24).max`.
        assertEq(_continuousIndexing.currentIndex(), prevIndex_);

        // If we keep warping, it should still return the last recorded index.
        vm.warp(block.timestamp + type(uint24).max);
        assertEq(_continuousIndexing.currentIndex(), prevIndex_);

        // We need to call `updateIndex()` to record a new `_latestUpdateTimestamp` and avoid overflowing uint32.
        prevIndex_ = _continuousIndexing.updateIndex();

        vm.warp(block.timestamp + type(uint24).max);

        uint128 nextIndex_ = _continuousIndexing.updateIndex();

        // The elapsed timestamp being now below uint32, the index should keep increasing and be computed properly.
        assertEq(nextIndex_, _getContinuousIndexAt(_rate, prevIndex_, type(uint24).max));
        assertGt(nextIndex_, prevIndex_);
    }
}
