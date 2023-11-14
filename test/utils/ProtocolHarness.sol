// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spog_, address mToken_) Protocol(spog_, mToken_) {}

    function setMintRequestOf(
        address minter_,
        uint256 amount_,
        uint256 createdAt_,
        address to_,
        uint256 gasLeft_
    ) external returns (uint256) {
        uint256 mintId_ = uint256(keccak256(abi.encodePacked(minter_, amount_, to_, createdAt_, gasLeft_)));
        mintRequestOf[minter_] = MintRequest(mintId_, to_, amount_, createdAt_);

        return mintId_;
    }

    function setCollateralOf(address minter_, uint256 amount_, uint256 lastUpdated_, uint256 penalizedUntil_) external {
        collateralOf[minter_] = CollateralBasic(amount_, lastUpdated_, penalizedUntil_);
    }

    function setCollateralOf(address minter_, uint256 amount_, uint256 lastUpdated_) external {
        collateralOf[minter_] = CollateralBasic(amount_, lastUpdated_, 0);
    }

    function setNormalizedPrincipalOf(address minter_, uint256 amount_) external {
        normalizedPrincipalOf[minter_] = amount_;
        totalNormalizedPrincipal += amount_;
    }

    function setMIndex(uint256 mIndex_) external {
        mIndex = mIndex_;
    }
}
