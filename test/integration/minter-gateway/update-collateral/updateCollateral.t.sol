// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../../../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../../../../src/libs/TTGRegistrarReader.sol";

import { IntegrationBaseSetup } from "../../IntegrationBaseSetup.t.sol";

contract UpdateCollateral_IntegrationTest is IntegrationBaseSetup {
    function test_updateCollateral_penaltyRateChange() external {
        address minter_ = _minters[0];
        uint256 collateral_ = 1_500_000e6;
        uint128 mintAmount_ = 1_000_000e6;

        _minterGateway.activateMinter(minter_);

        _updateCollateral(minter_, collateral_);
        assertEq(_minterGateway.collateralOf(minter_), collateral_);

        _mintM(minter_, mintAmount_, _alice);
        uint128 mintIndex_ = _minterGateway.latestIndex();
        uint128 principalAmount_ = ContinuousIndexingMath.divideUp(mintAmount_, mintIndex_);

        // 1 wei in excess cause we round up in favor of the protocol
        assertEq(_minterGateway.activeOwedMOf(minter_), mintAmount_ + 1);
        assertEq(_mToken.balanceOf(_alice), mintAmount_);

        vm.warp(block.timestamp + 25 hours);

        uint128 indexAfter25Hours_ = _getContinuousIndexAt(_baseMinterRate, mintIndex_, 25 hours);
        uint128 penaltyPrincipal_ = ContinuousIndexingMath.divideUp(
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_),
            indexAfter25Hours_
        );

        principalAmount_ += penaltyPrincipal_ + 1;

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        uint32 newPenaltyRate_ = 2_500; // 25% in bps
        _registrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, newPenaltyRate_);

        uint128 updateCollateralIndex_ = _minterGateway.latestIndex();
        uint256 updateCollateralTimestamp_ = _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        vm.warp(updateCollateralTimestamp_ + 25 hours);

        indexAfter25Hours_ = _getContinuousIndexAt(_baseMinterRate, updateCollateralIndex_, 25 hours);
        penaltyPrincipal_ = ContinuousIndexingMath.divideUp(
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_),
            indexAfter25Hours_
        );

        principalAmount_ += penaltyPrincipal_;

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );
    }

    function test_updateCollateral_updateCollateralIntervalChange() external {
        address minter_ = _minters[0];
        uint256 collateral_ = 1_500_000e6;
        uint128 mintAmount_ = 1_000_000e6;

        _minterGateway.activateMinter(minter_);

        _updateCollateral(minter_, collateral_);

        _mintM(minter_, mintAmount_, _alice);
        uint128 mintIndex_ = _minterGateway.latestIndex();
        uint128 principalAmount_ = ContinuousIndexingMath.divideUp(mintAmount_, mintIndex_);

        assertEq(_minterGateway.activeOwedMOf(minter_), mintAmount_ + 1);
        assertEq(_mToken.balanceOf(_alice), mintAmount_);

        vm.warp(block.timestamp + 25 hours);

        uint128 indexAfter25Hours_ = _getContinuousIndexAt(_baseMinterRate, mintIndex_, 25 hours);
        uint128 penaltyPrincipal_ = ContinuousIndexingMath.divideUp(
            _minterGateway.getPenaltyForMissedCollateralUpdates(minter_),
            indexAfter25Hours_
        );

        principalAmount_ += penaltyPrincipal_ + 1;

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 1 hours);

        vm.warp(block.timestamp + 12 hours);

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 48 hours);

        vm.warp(block.timestamp + 24 hours);

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );
    }

    function test_updateCollateral_mintRatioChange() external {
        address minter_ = _minters[0];
        uint256 collateral_ = 1_500_000e6;
        uint128 mintAmount_ = 1_000_000e6;

        _minterGateway.activateMinter(minter_);

        _updateCollateral(minter_, collateral_);
        assertEq(_minterGateway.collateralOf(minter_), collateral_);

        _mintM(minter_, mintAmount_, _alice);
        uint128 mintIndex_ = _minterGateway.latestIndex();
        uint128 principalAmount_ = ContinuousIndexingMath.divideUp(mintAmount_, mintIndex_);

        assertEq(_minterGateway.activeOwedMOf(minter_), mintAmount_ + 1);
        assertEq(_mToken.balanceOf(_alice), mintAmount_);

        vm.warp(block.timestamp + 12 hours);

        uint32 newMintRatio_ = 5_000; // 50% in bps
        _registrar.updateConfig(TTGRegistrarReader.MINT_RATIO, newMintRatio_);

        // Need to offset calculation by 1 hour since `_updateCollateral` warp the time by 1 hour.
        uint128 indexAfter13Hours_ = _getContinuousIndexAt(_baseMinterRate, mintIndex_, 13 hours);

        // penaltyBase = activeOwedMOf - maxAllowedActiveOwedMOf
        principalAmount_ += _getPenaltyPrincipal(
            ContinuousIndexingMath.multiplyUp(principalAmount_, indexAfter13Hours_) -
                _minterGateway.maxAllowedActiveOwedMOf(minter_),
            _penaltyRate,
            indexAfter13Hours_
        );

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        vm.warp(block.timestamp + 12 hours);

        _updateCollateral(minter_, collateral_ * 2);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );
    }
}
