// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Protocol } from "../../src/Protocol.sol";

contract ProtocolHarness is Protocol {
    constructor(address spogRegistrar_, address mToken_) Protocol(spogRegistrar_, mToken_) {}

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/

    function mintNonce() external view returns (uint48) {
        return _mintNonce;
    }

    function retrievalNonce() external view returns (uint48) {
        return _retrievalNonce;
    }

    function principalOfActiveOwedMOf(address minter_) external view returns (uint128 principalOfActiveOwedM_) {
        return _owedM[minter_].principalOfActive;
    }

    function rate() external view returns (uint32 rate_) {
        return _rate();
    }

    function internalCollateralOf(address minter_) external view returns (uint128 collateral_) {
        return _minterStates[minter_].collateral;
    }

    function totalPrincipalOfActiveOwedM() external view returns (uint128 totalPrincipalOfActiveOwedM_) {
        return _totalPrincipalOfActiveOwedM;
    }

    function getPrincipalAmountRoundedUp(uint128 amount_) external view returns (uint128 principalAmount_) {
        return _getPrincipalAmountRoundedUp(amount_);
    }

    function getMissedCollateralUpdateParameters(
        uint32 lastUpdateInterval_,
        uint40 lastUpdate_,
        uint40 lastPenalizedUntil_,
        uint32 newUpdateInterval_
    ) external view returns (uint40 missedIntervals_, uint40 missedUntil_) {
        return
            _getMissedCollateralUpdateParameters(
                lastUpdateInterval_,
                lastUpdate_,
                lastPenalizedUntil_,
                newUpdateInterval_
            );
    }

    /******************************************************************************************************************\
    |                                                     Setters                                                      |
    \******************************************************************************************************************/

    function setActiveMinter(address minter_, bool isActive_) external {
        _minterStates[minter_].isActive = isActive_;
    }

    function setMintNonce(uint256 nonce_) external {
        _mintNonce = uint48(nonce_);
    }

    function setMintProposalOf(
        address minter_,
        uint256 mintId_,
        uint256 amount_,
        uint256 createdAt_,
        address destination_
    ) external {
        _mintProposals[minter_] = MintProposal(uint48(mintId_), uint40(createdAt_), destination_, uint128(amount_));
    }

    function setCollateralOf(address minter_, uint256 collateral_) external {
        _minterStates[minter_].collateral = uint128(collateral_);
    }

    function setUpdateTimestampOf(address minter_, uint256 lastUpdated_) external {
        _minterStates[minter_].updateTimestamp = uint40(lastUpdated_);
    }

    function setUnfrozenTimeOf(address minter_, uint256 frozenTime_) external {
        _minterStates[minter_].frozenUntilTimestamp = uint40(frozenTime_);
    }

    function setLastCollateralUpdateIntervalOf(address minter_, uint256 updateInterval_) external {
        _minterStates[minter_].lastUpdateInterval = uint32(updateInterval_);
    }

    function setPenalizedUntilOf(address minter_, uint256 penalizedUntil_) external {
        _minterStates[minter_].penalizedUntilTimestamp = uint40(penalizedUntil_);
    }

    function setPrincipalOfActiveOwedMOf(address minter_, uint256 amount_) external {
        _owedM[minter_].principalOfActive = uint128(amount_);
    }

    function setTotalPrincipalOfActiveOwedM(uint256 amount_) external {
        _totalPrincipalOfActiveOwedM += uint128(amount_);
    }

    function setInactiveOwedMOf(address minter_, uint256 amount_) external {
        _owedM[minter_].inactive = uint128(amount_);
    }

    function setTotalInactiveOwedM(uint256 amount_) external {
        _totalInactiveOwedM = uint128(amount_);
    }

    function setTotalPendingRetrievalsOf(address minter_, uint256 amount_) external {
        _minterStates[minter_].totalPendingRetrievals = uint128(amount_);
    }

    function setLatestIndex(uint256 index_) external {
        _latestIndex = uint128(index_);
    }

    function setLatestRate(uint256 rate_) external {
        _latestRate = uint32(rate_);
    }

    function setRetrievalNonce(uint256 nonce_) external {
        _retrievalNonce = uint48(nonce_);
    }
}
