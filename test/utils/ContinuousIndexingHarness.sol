// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexing } from "../../src/abstract/ContinuousIndexing.sol";

contract ContinuousIndexingHarness is ContinuousIndexing {
    function rate() external view returns (uint32) {
        return _rate();
    }

    function _rate() internal view virtual override returns (uint32) {
        return 400; // 4% in bps
    }
}
