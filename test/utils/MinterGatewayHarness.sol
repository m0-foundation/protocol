// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { MinterGateway } from "../../src/MinterGateway.sol";

contract MinterGatewayHarness is MinterGateway {
    constructor(address ttgRegistrar_, address mToken_) MinterGateway(ttgRegistrar_, mToken_) {}

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/

    function getMissedCollateralUpdateParameters(
        uint40 lastUpdateTimestamp_,
        uint40 lastPenalizedUntil_,
        uint32 updateInterval_
    ) external view returns (uint40 missedIntervals_, uint40 missedUntil_) {
        return _getMissedCollateralUpdateParameters(lastUpdateTimestamp_, lastPenalizedUntil_, updateInterval_);
    }

    function getPrincipalAmountRoundedDown(uint240 amount_) external view returns (uint112 principalAmount_) {
        return _getPrincipalAmountRoundedDown(amount_);
    }

    function getPrincipalAmountRoundedUp(uint240 amount_) external view returns (uint112 principalAmount_) {
        return _getPrincipalAmountRoundedUp(amount_);
    }

    function internalCollateralOf(address minter_) external view returns (uint240) {
        return _minterStates[minter_].collateral;
    }

    function mintNonce() external view returns (uint48) {
        return _mintNonce;
    }

    function rate() external view returns (uint32) {
        return _rate();
    }

    function rawOwedMOf(address minter_) external view returns (uint256) {
        return _rawOwedM[minter_];
    }

    function retrievalNonce() external view returns (uint48) {
        return _retrievalNonce;
    }

    /******************************************************************************************************************\
    |                                                     Setters                                                      |
    \******************************************************************************************************************/

    function setIsActive(address minter_, bool isActive_) external {
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
        _minterStates[minter_].collateral = uint240(collateral_);
    }

    function setUpdateTimestampOf(address minter_, uint256 lastUpdated_) external {
        _minterStates[minter_].updateTimestamp = uint40(lastUpdated_);
    }

    function setLatestProposedRetrievalTimestamp(address minter_, uint256 latestProposedRetrieval_) external {
        _minterStates[minter_].latestProposedRetrievalTimestamp = uint40(latestProposedRetrieval_);
    }

    function setUnfrozenTimeOf(address minter_, uint256 frozenTime_) external {
        _minterStates[minter_].frozenUntilTimestamp = uint40(frozenTime_);
    }

    function setPenalizedUntilOf(address minter_, uint256 penalizedUntil_) external {
        _minterStates[minter_].penalizedUntilTimestamp = uint40(penalizedUntil_);
    }

    function setRawOwedMOf(address minter_, uint256 amount_) external {
        _rawOwedM[minter_] = uint240(amount_);
    }

    function setPrincipalOfTotalActiveOwedM(uint256 amount_) external {
        principalOfTotalActiveOwedM += uint112(amount_);
    }

    function setTotalInactiveOwedM(uint256 amount_) external {
        totalInactiveOwedM = uint128(amount_);
    }

    function setTotalPendingRetrievalsOf(address minter_, uint256 amount_) external {
        _minterStates[minter_].totalPendingRetrievals = uint128(amount_);
    }

    function setLatestIndex(uint256 index_) external {
        latestIndex = uint128(index_);
    }

    function setLatestRate(uint256 rate_) external {
        _latestRate = uint32(rate_);
    }

    function setIsDeactivated(address minter_, bool isDeactivated_) external {
        _minterStates[minter_].isDeactivated = isDeactivated_;
    }

    function setLastSignatureTimestamp(address minter_, address validator_, uint256 timestamp_) external {
        _lastSignatureTimestamp[minter_][validator_] = timestamp_;
    }
}
