// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../../../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../../../../src/libs/TTGRegistrarReader.sol";

import { IntegrationBaseSetup } from "../../IntegrationBaseSetup.t.sol";

contract DeactivateMinter_IntegrationTest is IntegrationBaseSetup {
    function test_deactivateMinter_updateCollateralIntervalChange() external {
        address minter_ = _minters[0];
        uint256 collateral_ = 1_500_000e6;
        uint128 mintAmount_ = 1_000_000e6;

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

        principalAmount_ += penaltyPrincipal_;

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 48 hours);

        vm.warp(vm.getBlockTimestamp() + 36 hours);

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, minter_);

        vm.prank(_alice);
        _minterGateway.deactivateMinter(minter_);

        assertEq(
            _minterGateway.inactiveOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        assertEq(_minterGateway.activeOwedMOf(minter_), 0);
        assertTrue(_minterGateway.isDeactivatedMinter(minter_));
    }
}
