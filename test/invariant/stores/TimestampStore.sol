// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
/// save the current timestamp in a contract with persistent storage.
contract TimestampStore {
    uint32 public currentTimestamp;

    constructor() {
        currentTimestamp = uint32(block.timestamp);
    }

    function increaseCurrentTimestamp(uint32 timeJump_) external returns (uint32) {
        return currentTimestamp += timeJump_;
    }
}
