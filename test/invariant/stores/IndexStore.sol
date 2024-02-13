// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

/// @dev Contract to share index between invariants and handlers
contract IndexStore {
    uint128 public currentEarnerIndex;
    uint128 public currentMinterIndex;

    function setEarnerIndex(uint128 index_) external returns (uint128) {
        return currentEarnerIndex = index_;
    }

    function setMinterIndex(uint128 index_) external returns (uint128) {
        return currentMinterIndex = index_;
    }
}
