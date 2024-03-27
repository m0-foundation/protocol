// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../../../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../../../../src/libs/TTGRegistrarReader.sol";

import { IntegrationBaseSetup } from "../../IntegrationBaseSetup.t.sol";

contract BurnM_IntegrationTest is IntegrationBaseSetup {
    function test_burnM_updateCollateralIntervalChange() external {
        address minter_ = _minters[0];
        uint256 collateral_ = 1_500_000e6;
        uint128 mintAmount_ = 1_000_000e6;
        uint128 burnAmount_ = 250_000e6;

        _minterGateway.activateMinter(minter_);

        _updateCollateral(minter_, collateral_);

        _mintM(minter_, mintAmount_, _alice);
        uint128 mintIndex_ = _minterGateway.latestIndex();
        uint112 principalAmount_ = ContinuousIndexingMath.divideUp(mintAmount_, mintIndex_);

        assertEq(_minterGateway.activeOwedMOf(minter_), mintAmount_ + 1);
        assertEq(_mToken.balanceOf(_alice), mintAmount_);

        vm.warp(vm.getBlockTimestamp() + 25 hours);

        uint128 indexAfter25Hours_ = _getContinuousIndexAt(_baseMinterRate, mintIndex_, 25 hours);
        uint112 penaltyPrincipal_ = ContinuousIndexingMath.divideDown(
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_),
            indexAfter25Hours_
        );

        uint112 burnAmountPrincipal_ = ContinuousIndexingMath.divideDown(burnAmount_, indexAfter25Hours_);

        principalAmount_ += penaltyPrincipal_;
        principalAmount_ -= burnAmountPrincipal_;

        vm.prank(_alice);
        _minterGateway.burnM(minter_, burnAmount_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        assertEq(_mToken.balanceOf(_alice), mintAmount_ -= burnAmount_);

        uint128 burnIndex_ = _minterGateway.latestIndex();

        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 hours);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        uint128 indexAfter12Hours_ = _getContinuousIndexAt(_baseMinterRate, burnIndex_, 12 hours);

        penaltyPrincipal_ = ContinuousIndexingMath.divideDown(
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_),
            indexAfter12Hours_
        );

        burnAmountPrincipal_ = ContinuousIndexingMath.divideDown(burnAmount_, indexAfter12Hours_);

        principalAmount_ += penaltyPrincipal_;
        principalAmount_ -= burnAmountPrincipal_;

        vm.prank(_alice);
        _minterGateway.burnM(minter_, burnAmount_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        assertEq(_mToken.balanceOf(_alice), mintAmount_ -= burnAmount_);

        burnIndex_ = _minterGateway.latestIndex();

        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 48 hours);

        vm.warp(vm.getBlockTimestamp() + 24 hours);

        uint128 indexAfter24Hours_ = _getContinuousIndexAt(_baseMinterRate, burnIndex_, 24 hours);
        burnAmountPrincipal_ = ContinuousIndexingMath.divideDown(burnAmount_, indexAfter24Hours_);

        principalAmount_ -= burnAmountPrincipal_;

        vm.prank(_alice);
        _minterGateway.burnM(minter_, burnAmount_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        assertEq(_mToken.balanceOf(_alice), mintAmount_ -= burnAmount_);
    }
}
