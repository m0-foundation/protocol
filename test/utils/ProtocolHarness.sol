// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spogRegistrar_, address mToken_) Protocol(spogRegistrar_, mToken_) {}

    function mintNonce() external view returns (uint48) {
        return _mintNonce;
    }

    function retrievalNonce() external view returns (uint48) {
        return _retrievalNonce;
    }

    function setActiveMinter(address minter_, bool isActive_) external {
        _minterStates[minter_].isActive = isActive_;
    }

    function setMintProposalOf(
        address minter_,
        uint256 amount_,
        uint256 createdAt_,
        address destination_
    ) external returns (uint48 mintId_) {
        mintId_ = ++_mintNonce;

        _mintProposals[minter_] = MintProposal(uint48(mintId_), uint40(createdAt_), destination_, uint128(amount_));
    }

    function setCollateralOf(address minter_, uint256 collateral_) external {
        _minterStates[minter_].collateral = uint128(collateral_);
    }

    function setCollateralUpdateOf(address minter_, uint256 lastUpdated_) external {
        _minterStates[minter_].updateTimestamp = uint40(lastUpdated_);
    }

    function setLastCollateralUpdateIntervalOf(address minter_, uint256 updateInterval_) external {
        _minterStates[minter_].lastUpdateInterval = uint32(updateInterval_);
    }

    function setPenalizedUntilOf(address minter_, uint256 penalizedUntil_) external {
        _minterStates[minter_].penalizedUntilTimestamp = uint40(penalizedUntil_);
    }

    function setPrincipalOfActiveOwedMOf(address minter_, uint256 amount_) external {
        _owedM[minter_].principalOfActive = uint128(amount_);
        _totalPrincipalOfActiveOwedM += uint128(amount_); // TODO: fix this side effect.
    }

    function setLatestIndex(uint256 index_) external {
        _latestIndex = uint128(index_);
    }

    function setLatestRate(uint256 rate_) external {
        _latestRate = uint32(rate_);
    }

    function principalOfActiveOwedMOf(address minter_) external view returns (uint128 principalOfActiveOwedM_) {
        return _owedM[minter_].principalOfActive;
    }

    function rate() external view returns (uint32 rate_) {
        return _rate();
    }
}
