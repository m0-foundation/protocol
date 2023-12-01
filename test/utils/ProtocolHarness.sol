// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spogRegistrar_, address mToken_) Protocol(spogRegistrar_, mToken_) {}

    function mintNonce() external view returns (uint256) {
        return _mintNonce;
    }

    function retrievalNonce() external view returns (uint256) {
        return _retrievalNonce;
    }

    function getMintId(
        address minter_,
        uint256 amount_,
        address destination_,
        uint256 nonce_
    ) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(minter_, amount_, destination_, nonce_)));
    }

    function getRetrievalId(address minter_, uint256 collateral_, uint256 nonce_) external pure returns (uint256) {
        return uint256(keccak256(abi.encode(minter_, collateral_, nonce_)));
    }

    function setActiveMinter(address minter_, bool isActive_) external {
        _isActiveMinter[minter_] = isActive_;
    }

    function setMintProposalOf(
        address minter_,
        uint256 amount_,
        uint256 createdAt_,
        address destination_
    ) external returns (uint256 mintId_) {
        mintId_ = uint256(keccak256(abi.encodePacked(minter_, amount_, destination_, createdAt_)));

        _mintProposals[minter_] = MintProposal(mintId_, destination_, amount_, createdAt_);
    }

    function setCollateralOf(address minter_, uint256 collateral_) external {
        _collaterals[minter_] = collateral_;
    }

    function setLastCollateralUpdateOf(address minter_, uint256 lastUpdated_) external {
        _lastCollateralUpdates[minter_] = lastUpdated_;
    }

    function setLastUpdateIntervalOf(address minter_, uint256 updateInterval_) external {
        _lastUpdateIntervals[minter_] = updateInterval_;
    }

    function setPenalizedUntilOf(address minter_, uint256 penalizedUntil_) external {
        _penalizedUntilTimestamps[minter_] = penalizedUntil_;
    }

    function setPrincipalOfActiveOwedMOf(address minter_, uint256 amount_) external {
        _principalOfActiveOwedM[minter_] = amount_;
        _totalPrincipalOfActiveOwedM += amount_; // TODO: fix this side effect.
    }

    function setLatestIndex(uint256 index_) external {
        _latestIndex = index_;
    }

    function setLatestRate(uint256 rate_) external {
        _latestRate = rate_;
    }

    function principalOfActiveOwedMOf(address minter_) external view returns (uint256 principalOfActiveOwedM_) {
        return _principalOfActiveOwedM[minter_];
    }
}
