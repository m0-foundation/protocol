// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";

// Note: This harness contract is needed cause internal library functions can be inlined by the compiler
//       and won't be picked up by forge coverage
// See: https://github.com/foundry-rs/foundry/issues/6308#issuecomment-1866878768
contract ContinuousIndexingMathHarness {
    function divideDown(uint240 x, uint128 index) external pure returns (uint112 z) {
        return ContinuousIndexingMath.divideDown(x, index);
    }

    function divideUp(uint240 x, uint128 index) external pure returns (uint112 z) {
        return ContinuousIndexingMath.divideUp(x, index);
    }

    function multiplyDown(uint112 x, uint128 index) external pure returns (uint240 z) {
        return ContinuousIndexingMath.multiplyDown(x, index);
    }

    function multiplyUp(uint112 x, uint128 index) external pure returns (uint240 z) {
        return ContinuousIndexingMath.multiplyUp(x, index);
    }

    function multiplyIndicesDown(uint128 index, uint48 deltaIndex) external pure returns (uint144 z) {
        return ContinuousIndexingMath.multiplyIndicesDown(index, deltaIndex);
    }

    function multiplyIndicesUp(uint128 index, uint48 deltaIndex) external pure returns (uint144 z) {
        return ContinuousIndexingMath.multiplyIndicesUp(index, deltaIndex);
    }

    function getContinuousIndex(uint64 yearlyRate, uint32 time) external pure returns (uint48 index) {
        return ContinuousIndexingMath.getContinuousIndex(yearlyRate, time);
    }

    function exponent(uint72 x) external pure returns (uint48 y) {
        return ContinuousIndexingMath.exponent(x);
    }

    function convertToBasisPoints(uint64 input) external pure returns (uint40) {
        return ContinuousIndexingMath.convertToBasisPoints(input);
    }

    function convertFromBasisPoints(uint32 input) external pure returns (uint64) {
        return ContinuousIndexingMath.convertFromBasisPoints(input);
    }
}
