// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

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
}
