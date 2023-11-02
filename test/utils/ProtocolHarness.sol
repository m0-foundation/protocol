// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spog_, address mToken_) Protocol(spog_, mToken_) {}

    function setMintRequest(
        address minter,
        uint256 amount,
        uint256 createdAt,
        address to,
        uint256 gasLeft
    ) external returns (uint256) {
        uint256 mintId = uint256(keccak256(abi.encodePacked(minter, amount, to, createdAt, gasLeft)));
        mintRequests[minter] = MintRequest(mintId, to, amount, createdAt);

        return mintId;
    }

    function setCollateral(address minter, uint256 amount, uint256 lastUpdated) external {
        collateral[minter] = CollateralBasic(amount, lastUpdated);
    }

    function setNormalizedPrincipal(address minter, uint256 amount) external {
        normalizedPrincipal[minter] = amount;
        totalNormalizedPrincipal += amount;
    }

    function setMIndex(uint256 index) external {
        mIndex = index;
    }
}
