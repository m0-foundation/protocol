// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spog_, address mToken_) Protocol(spog_, mToken_) {}

    function setMintProposalOf(
        address minter_,
        uint256 amount_,
        uint256 createdAt_,
        address destination_
    ) external returns (uint256 mintId_) {
        mintId_ = uint256(keccak256(abi.encodePacked(minter_, amount_, destination_, createdAt_)));

        _mintProposals[minter_] = MintProposal(mintId_, destination_, amount_, createdAt_);
    }

    function setCollateralOf(
        address minter_,
        uint256 collateral_,
        uint256 lastUpdated_,
        uint256 penalizedUntil_
    ) external {
        _collaterals[minter_] = MinterCollateral(collateral_, lastUpdated_, penalizedUntil_);
    }

    function setCollateralOf(address minter_, uint256 collateral_, uint256 lastUpdated_) external {
        _collaterals[minter_] = MinterCollateral(collateral_, lastUpdated_, 0);
    }

    function setPrincipalOfActiveOwedMOf(address minter_, uint256 amount_) external {
        _principalOfActiveOwedM[minter_] = amount_;
        _totalPrincipalOfActiveOwedM += amount_; // TODO: fix this side effect.
    }

    function setIndex(uint256 index_) external {
        _latestIndex = index_;
    }

    function principalOfActiveOwedMOf(address minter_) external view returns (uint256 principalOfActiveOwedM_) {
        return _principalOfActiveOwedM[minter_];
    }
}
