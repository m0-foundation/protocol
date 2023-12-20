// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Protocol } from "../../../src/Protocol.sol";
import { IContinuousIndexing } from "../../../src/interfaces/IContinuousIndexing.sol";
import { ContinuousIndexing } from "../../../src/ContinuousIndexing.sol";

contract ProtocolHarness is Protocol {
    constructor(address spogRegistrar_, address mToken_) Protocol(spogRegistrar_, mToken_) {}

    uint256 internal _fixedIndex;

    // --- ContinuousIndexing
    function setter_latestIndex(uint256 latestIndex_) external {
        _latestIndex = latestIndex_;
    }

    function setter_latestRate(uint256 latestRate_) external {
        _latestRate = latestRate_;
    }

    function setter_latestUpdateTimestamp(uint256 latestUpdateTimestamp_) external {
        _latestUpdateTimestamp = latestUpdateTimestamp_;
    }

    // --- Protocol

    function setter_isActiveMinter(address minter_, bool isActiveMinter_) external {
        _isActiveMinter[minter_] = isActiveMinter_;
    }

    function setter_collateral(address minter_, uint256 collateral_) external {
        _collaterals[minter_] = collateral_;
    }

    function setter_inactiveOwedM(address minter_, uint256 inactiveOwedM_) external {
        _inactiveOwedM[minter_] = inactiveOwedM_;
    }

    function setter_principalOfActiveOwedM(address minter_, uint256 activeOwedM_) external {
        _principalOfActiveOwedM[minter_] = activeOwedM_;
    }

    function getter_principalOfActiveOwedM(address minter_) external view returns (uint256 activeOwedM_) {
        return _principalOfActiveOwedM[minter_];
    }

    function setter_totalPendingCollateralRetrieval(
        address minter_,
        uint256 totalPendingCollateralRetrieval_
    ) external {
        _totalPendingCollateralRetrieval[minter_] = totalPendingCollateralRetrieval_;
    }

    function setter_lastUpdateInterval(address minter_, uint256 updateInterval_) external {
        _lastUpdateIntervals[minter_] = updateInterval_;
    }

    function setter_lastUpdateTimestamp(address minter_, uint256 lastUpdate_) external {
        _lastCollateralUpdates[minter_] = lastUpdate_;
    }

    function setter_penalizedUntilTimestamp(address minter_, uint256 penalizedUntil_) external {
        _penalizedUntilTimestamps[minter_] = penalizedUntil_;
    }

    function setter_unfrozenTimestamp(address minter_, uint256 unfrozenTime_) external {
        _unfrozenTimestamps[minter_] = unfrozenTime_;
    }

    function setter_mintProposals(
        address minter_,
        uint256 amount_,
        uint256 createdAt_,
        address destination_
    ) external returns (uint256 mintId_) {
        mintId_ = uint256(keccak256(abi.encodePacked(minter_, amount_, destination_, createdAt_)));

        _mintProposals[minter_] = MintProposal(mintId_, destination_, amount_, createdAt_);
    }

    function setter_totalInactiveOwedM(uint256 totalInactiveOwedM_) external {
        _totalInactiveOwedM = totalInactiveOwedM_;
    }

    function setter_totalPrincipalOfActiveOwedM(uint256 totalPrincipalOfActiveOwedM_) external {
        _totalPrincipalOfActiveOwedM = totalPrincipalOfActiveOwedM_;
    }

    function getter_totalPrincipalOfActiveOwedM() external view returns (uint256 totalPrincipalOfActiveOwedM_) {
        return _totalPrincipalOfActiveOwedM;
    }

    function setter_pendingRetrievals(address minter_, uint256 retrievalId_, uint256 amount_) external {
        _pendingRetrievals[minter_][retrievalId_] = amount_;
    }

    // --- external Protocol Functions

    function external_getPresentValue(uint256 principalValue_) external view returns (uint256 presentValue_) {
        return _getPresentValue(principalValue_);
    }

    function external_getPrincipalValue(uint256 principalValue_) external view returns (uint256 presentValue_) {
        return _getPrincipalValue(principalValue_);
    }

    function external_rate() external view returns (uint256 rate_) {
        return _rate();
    }

    function external_getPenaltyBaseAndTimeForMissedCollateralUpdates(
        address minter_
    ) external view returns (uint256 penaltyBase_, uint256 penalizedUntil_) {
        return _getPenaltyBaseAndTimeForMissedCollateralUpdates(minter_);
    }

    function external_imposePenaltyIfMissedCollateralUpdates(address minter_) external {
        _imposePenaltyIfMissedCollateralUpdates(minter_);
    }

    function external_imposePenalty(address minter_, uint256 penaltyBase_) external {
        _imposePenalty(minter_, penaltyBase_);
    }

    function external_mintProposal(address minter_) external view returns (uint256 mintId_, address destination_, uint256 amount_, uint256 createdAt_) {
        mintId_ = _mintProposals[minter_].id;
        destination_ = _mintProposals[minter_].destination;
        amount_ = _mintProposals[minter_].amount;
        createdAt_ = _mintProposals[minter_].createdAt;
    }

    // overwritten compunding functions functions to set expected values
    function override_fixedIndex(uint256 fixedIndex_) external {
        _fixedIndex = fixedIndex_;
    }

    function override_fixedIndex() external {
        _fixedIndex = 1e18;
    }

    function currentIndex()
        public
        view
        virtual
        override(IContinuousIndexing, ContinuousIndexing)
        returns (uint256 currentIndex_)
    {
        if (_fixedIndex != 0) {
          //  return _fixedIndex;
        }

        return super.currentIndex();
    }
}
