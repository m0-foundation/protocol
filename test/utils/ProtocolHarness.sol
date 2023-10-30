// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spog_, address mToken_) Protocol(spog_, mToken_) {}

    function setMintRequest(address minter, uint256 amount, uint256 createdAt, address to) external {
        mintRequests[minter] = MintRequest(amount, createdAt, to);
    }

    function setCollateral(address minter, uint256 amount, uint256 lastUpdated) external {
        collateral[minter] = CollateralBasic(amount, lastUpdated);
    }

    function setNormalizedPrinciapl(address minter, uint256 amount) external {
        normalizedPrincipal[minter] = amount;
        totalNormalizedPrincipal += amount;
    }

    function setMIndex(uint256 index) external {
        mIndex = index;
    }
}
