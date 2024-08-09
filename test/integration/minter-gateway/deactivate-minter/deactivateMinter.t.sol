// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../../../src/libs/ContinuousIndexingMath.sol";
import { RegistrarReader } from "../../../../src/libs/RegistrarReader.sol";

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
        uint240 activeOwedM_ = _minterGateway.activeOwedMOf(minter_);

        // 1 wei in excess cause we round up in favor of the protocol
        assertEq(activeOwedM_, mintAmount_ + 1);
        assertEq(_mToken.balanceOf(_alice), mintAmount_);

        vm.warp(vm.getBlockTimestamp() + 25 hours);

        activeOwedM_ = _minterGateway.activeOwedMOf(minter_);
        uint128 indexAfter25Hours_ = _getContinuousIndexAt(_baseMinterRate, mintIndex_, 25 hours);
        uint112 missedUpdatePenalty_ = ContinuousIndexingMath.divideUp(
            (activeOwedM_ * _penaltyRate) / ONE,
            indexAfter25Hours_
        );

        principalAmount_ += missedUpdatePenalty_;

        uint40 timeSinceLastUpdate_ = uint40(
            vm.getBlockTimestamp() - _minterGateway.collateralUpdateTimestampOf(minter_) - 24 hours
        );

        uint112 undercollateralizedPenalty_ = (((principalAmount_ * timeSinceLastUpdate_) / 24 hours) * _penaltyRate) /
            ONE;

        principalAmount_ += undercollateralizedPenalty_;

        _updateCollateral(minter_, collateral_);

        assertEq(
            _minterGateway.activeOwedMOf(minter_),
            ContinuousIndexingMath.multiplyUp(principalAmount_, _minterGateway.currentIndex())
        );

        _registrar.updateConfig(RegistrarReader.UPDATE_COLLATERAL_INTERVAL, 48 hours);

        vm.warp(vm.getBlockTimestamp() + 36 hours);

        _registrar.removeFromList(RegistrarReader.MINTERS_LIST, minter_);

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
