// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { MinterGateway } from "../../src/MinterGateway.sol";

contract MinterGatewayHarness is MinterGateway {
    constructor(address ttgRegistrar_, address mToken_) MinterGateway(ttgRegistrar_, mToken_) {}

    /******************************************************************************************************************\
    |                                                     Getters                                                      |
    \******************************************************************************************************************/

    function getPenalty(
        address minter_
    )
        external
        view
        returns (
            uint112 penaltyPrincipal_,
            uint112 principalOfExcessOwedM_,
            uint40 penalizeFrom_,
            uint40 penalizeUntil_
        )
    {
        return _getPenalty(minter_);
    }

    function getPenalty(
        uint256 updateTimestamp_,
        uint256 penalizedUntilTimestamp_,
        uint256 principalOfActiveOwedM_,
        uint256 maxAllowedActiveOwedM_,
        uint256 newUpdateInterval_
    )
        external
        view
        returns (
            uint112 penaltyPrincipal_,
            uint112 principalOfExcessOwedM_,
            uint40 penalizeFrom_,
            uint40 penalizeUntil_
        )
    {
        return
            _getPenalty(
                uint40(updateTimestamp_),
                uint40(penalizedUntilTimestamp_),
                uint112(principalOfActiveOwedM_),
                maxAllowedActiveOwedM_,
                uint32(newUpdateInterval_)
            );
    }

    function getPresentAmount(uint256 principalAmount_) external view returns (uint240) {
        return _getPresentAmount(uint112(principalAmount_));
    }

    function getPrincipalAmountRoundedUp(uint256 amount_) external view returns (uint112 principalAmount_) {
        return _getPrincipalAmountRoundedUp(uint240(amount_));
    }

    function internalCollateralOf(address minter_) external view returns (uint240 collateral_) {
        return _minterStates[minter_].collateral;
    }

    function mintNonce() external view returns (uint48) {
        return _mintNonce;
    }

    function rate() external view returns (uint32 rate_) {
        return _rate();
    }

    function rawOwedMOf(address minter_) external view returns (uint256 rawOwedMOf_) {
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

    function setUnfrozenTimeOf(address minter_, uint256 frozenTime_) external {
        _minterStates[minter_].frozenUntilTimestamp = uint40(frozenTime_);
    }

    function setPenalizedUntilOf(address minter_, uint256 penalizedUntil_) external {
        _minterStates[minter_].penalizedUntilTimestamp = uint40(penalizedUntil_);
    }

    function setRawOwedMOf(address minter_, uint256 amount_) external {
        _rawOwedM[minter_] = uint240(amount_);
    }

    function setTotalPrincipalOfActiveOwedM(uint256 amount_) external {
        _totalPrincipalOfActiveOwedM += uint112(amount_);
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

    function setIsDeactivated(address minter_, bool isDeactivated_) external {
        _minterStates[minter_].isDeactivated = isDeactivated_;
    }
}
