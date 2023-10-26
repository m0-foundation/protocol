// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spog_, address mToken_) Protocol(spog_, mToken_) {}

    function setCollateral(address minter, uint256 amount, uint256 lastUpdated) external {
        collateral[minter] = CollateralBasic(amount, lastUpdated);
    }
}
