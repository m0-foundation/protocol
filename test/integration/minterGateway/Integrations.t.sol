// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../../lib/forge-std/src/Test.sol";

import { SPOGRegistrarReader } from "../../../src/libs/SPOGRegistrarReader.sol";

import { MockSPOGRegistrar } from "./../../utils/Mocks.sol";

import { IntegrationBaseSetup } from "../IntegrationBaseSetup.t.sol";

contract IntegrationTests is IntegrationBaseSetup {
    function test_compliantMinter() external {
        _protocol.activateMinter(_minters[0]);
        _protocol.activateMinter(_minters[1]);

        vm.prank(_alice);
        _mToken.startEarning();

        vm.warp(block.timestamp + 2 hours); // 2 hours after deploy, minter collects signatures.

        uint256 collateral = 1_000_000e6;
        uint256 lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        uint256 mintAmount = 500_000e6;
        _mintM(_minters[0], mintAmount, _alice);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 500_000_000001); // ~500k
        assertEq(_mToken.balanceOf(_alice), 500_000_000000); // 500k
        assertEq(_mToken.balanceOf(_vault), 1);

        vm.warp(lastUpdateTimestamp + 18 hours); // start collecting signatures for next collateral update
        collateral = 1_200_000e6;
        _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        mintAmount = 200_000e6;
        _mintM(_minters[0], mintAmount, _bob);

        assertEq(
            _protocol.activeOwedMOf(_minters[0]),
            _mToken.balanceOf(_alice) + _mToken.balanceOf(_bob) + _mToken.balanceOf(_vault)
        );

        // Mint M to alice, so she can repay owed M of first minter.
        vm.warp(block.timestamp + 1 hours); // 1 hour later,second minter updates collateral and proposes mint
        _updateCollateral(_minters[1], collateral);

        vm.warp(block.timestamp + 1 hours);

        mintAmount = 500_000e6;
        _mintM(_minters[1], mintAmount, _alice);

        // Alice repaid active owed M of minter
        uint256 aliceBalance = _mToken.balanceOf(_alice);
        uint256 minterOwedM = _protocol.activeOwedMOf(_minters[0]);

        vm.prank(_alice);
        _protocol.burnM(_minters[0], aliceBalance);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 0);
        assertEq(_mToken.balanceOf(_alice), aliceBalance - minterOwedM);

        // Minter can mint again without imposing any penalties for missed collateral updates
        vm.warp(block.timestamp + 60 days);

        collateral = 1_000_000e6;
        _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + 1 hours);

        mintAmount = 900_000e6;
        _mintM(_minters[0], mintAmount, _alice);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 900_000_000001); // ~900k
    }

    function test_nonCompliantMintersPayPenalties() external {
        // NOTE:  Compare three minters:
        //        1. _minters[0] - compliant minter
        //        2. _minters[1] - non-compliant minter, undercollateralized
        //        3. _minters[2] - non-compliant minter, missed collateral update intervals
        _protocol.activateMinter(_minters[0]);
        _protocol.activateMinter(_minters[1]);
        _protocol.activateMinter(_minters[2]);

        vm.prank(_alice);
        _mToken.startEarning();

        vm.warp(block.timestamp + 2 hours); // 2 hours after deploy, minters collect signatures.

        uint256 collateral = 1_500_000e6;
        uint256 lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);
        _updateCollateral(_minters[1], collateral);
        _updateCollateral(_minters[2], collateral);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minters propose mints.

        uint256 mintAmount = 500_000e6;
        address[] memory testMinters = new address[](3);
        testMinters[0] = _minters[0];
        testMinters[1] = _minters[1];
        testMinters[2] = _minters[2];
        uint256[] memory mintAmounts = new uint256[](3);
        mintAmounts[0] = mintAmounts[1] = mintAmounts[2] = mintAmount;

        address[] memory recipients = new address[](3);
        recipients[0] = recipients[1] = recipients[2] = _alice;
        _batchMintM(testMinters, mintAmounts, recipients);

        assertEq(_protocol.activeOwedMOf(_minters[0]), _protocol.activeOwedMOf(_minters[1]));
        assertEq(_protocol.activeOwedMOf(_minters[0]), _protocol.activeOwedMOf(_minters[2]));

        vm.warp(lastUpdateTimestamp + 18 hours);
        lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);
        _updateCollateral(_minters[1], collateral);

        vm.warp(lastUpdateTimestamp + 15 hours);
        lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);
        _updateCollateral(_minters[1], collateral / 10); // minter is undercollateralized.
        _updateCollateral(_minters[2], collateral); // minter missed collateral update intervals.

        assertGt(_protocol.activeOwedMOf(_minters[1]), _protocol.activeOwedMOf(_minters[0]));
        assertGt(_protocol.activeOwedMOf(_minters[2]), _protocol.activeOwedMOf(_minters[0]));
        assertGt(_protocol.activeOwedMOf(_minters[2]), _protocol.activeOwedMOf(_minters[1]));

        assertEq(
            _protocol.activeOwedMOf(_minters[0]) +
                _protocol.activeOwedMOf(_minters[1]) +
                _protocol.activeOwedMOf(_minters[2]),
            _mToken.balanceOf(_alice) + _mToken.balanceOf(_vault)
        );
    }

    function test_deactivateMinterAndPayTheirInactiveOwedM() external {
        _protocol.activateMinter(_minters[0]);

        vm.warp(block.timestamp + 2 hours); // 2 hours after deploy, minter collects signatures.

        uint256 collateral = 1_000_000e6;
        uint256 lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        uint256 mintAmount = 500_000e6;
        _mintM(_minters[0], mintAmount, _alice);

        vm.warp(lastUpdateTimestamp + 90 days);

        uint256 totalMSupplyBeforeDeactivation = _mToken.totalSupply();
        uint256 totalOwedMBeforeDeactivation = _protocol.totalOwedM();
        uint256 vaultBalanceBeforeDeactivation = _mToken.balanceOf(_vault);

        assertGt(_protocol.totalOwedM(), _mToken.totalSupply());
        // TODO: should it be equal ?
        assertGt(_protocol.totalActiveOwedM(), _mToken.totalSupply());
        assertEq(_protocol.totalInactiveOwedM(), 0);
        assertEq(_protocol.activeOwedMOf(_minters[0]), _protocol.totalOwedM());
        assertEq(_protocol.inactiveOwedMOf(_minters[0]), 0);

        // TTG removes minter from the protocol.
        _registrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minters[0]);
        // Minter is deactivated in the protocol
        _protocol.deactivateMinter(_minters[0]);

        uint256 totalOwedMAfterDeactivation = _protocol.totalOwedM();
        uint256 vaultBalanceAfterDeactivation = _mToken.balanceOf(_vault);

        assertEq(_protocol.totalOwedM(), _mToken.totalSupply());

        // Vault gets penalty plus delta of cash flows before deactivation
        assertEq(
            vaultBalanceAfterDeactivation - vaultBalanceBeforeDeactivation,
            (totalOwedMAfterDeactivation - totalOwedMBeforeDeactivation) +
                (totalOwedMBeforeDeactivation - totalMSupplyBeforeDeactivation)
        );

        assertEq(_mToken.earnerRate(), 0); // there is no active owed M left.

        // Activate second minter to repay owedM of the first minter.
        _protocol.activateMinter(_minters[1]);
        _updateCollateral(_minters[1], collateral);
        _mintM(_minters[1], mintAmount, _alice);

        // Now alice has sufficient M to repay owedM of the first minter.
        uint256 aliceBalance = _mToken.balanceOf(_alice);
        vm.prank(_alice);
        _protocol.burnM(_minters[0], aliceBalance);

        assertEq(_protocol.totalOwedM(), _mToken.totalSupply());
        assertEq(_protocol.totalInactiveOwedM(), 0);
        assertEq(_protocol.inactiveOwedMOf(_minters[0]), 0);
    }

    function test_retrieveCollateral() external {
        _protocol.activateMinter(_minters[0]);

        uint256 collateral = 1_000_000e6;
        uint256 lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        uint256 mintAmount = 500_000e6;
        _mintM(_minters[0], mintAmount, _alice);

        assertEq(_protocol.totalOwedM(), _mToken.totalSupply());

        assertEq(_protocol.maxAllowedActiveOwedMOf(_minters[0]), 900_000e6);

        vm.prank(_minters[0]);
        uint256 retrievalAmount = 400_000e6;
        uint48 retrievalId = _protocol.proposeRetrieval(retrievalAmount);

        vm.warp(lastUpdateTimestamp + 18 hours); // provide new collateral update

        lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);

        assertEq(_protocol.totalOwedM(), _mToken.totalSupply());
        assertEq(_protocol.maxAllowedActiveOwedMOf(_minters[0]), 540_000000000);

        vm.warp(lastUpdateTimestamp + 18 hours); // provide new collateral update

        uint256[] memory retrievalIds = new uint256[](1);
        retrievalIds[0] = retrievalId;
        _updateCollateral(_minters[0], collateral - retrievalAmount, retrievalIds);

        assertEq(_protocol.collateralOf(_minters[0]), 600_000e6);
        assertEq(_protocol.maxAllowedActiveOwedMOf(_minters[0]), 540_000000000);
        assertEq(_protocol.activeOwedMOf(_minters[0]), 500_176971951);
    }

    function test_cancelMintProposalsAndFreezeMinter() external {
        _protocol.activateMinter(_minters[0]);

        uint256 collateral = 1_000_000e6;
        uint256 mintAmount = 500_000e6;
        uint256 lastUpdateTimestamp = _updateCollateral(_minters[0], collateral);

        vm.warp(lastUpdateTimestamp + 1 hours); // 1 hour later, minter proposes a mint.

        vm.prank(_minters[0]);
        uint256 mintId = _protocol.proposeMint(mintAmount, _alice);

        vm.warp(block.timestamp + 1 hours); // 1 hour after the mint delay, validator cancels mint

        vm.prank(_validators[0]);
        _protocol.cancelMint(_minters[0], mintId);

        // Validator freezes minter every hour
        for (uint256 i; i < 12; ++i) {
            vm.warp(block.timestamp + 1 hours);

            vm.prank(_validators[0]);
            _protocol.freezeMinter(_minters[0]);

            assertEq(_protocol.isFrozenMinter(_minters[0]), true);
            assertEq(_protocol.unfrozenTimeOf(_minters[0]), block.timestamp + _minterFreezeTime);
        }

        // Frozen minter needs to continue updating collateral to avoid penalties
        _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + _minterFreezeTime / 2);

        // Minter is still frozen
        assertEq(_protocol.isFrozenMinter(_minters[0]), true);

        // Frozen minter needs to continue updating collateral to avoid penalties
        _updateCollateral(_minters[0], collateral);

        vm.warp(block.timestamp + _minterFreezeTime / 2 + 1);

        // Minter is unfrozen and can mint now
        assertEq(_protocol.isFrozenMinter(_minters[0]), false);

        _mintM(_minters[0], mintAmount, _alice);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 500_000_000001); // ~500k
    }

    function _updateCollateral(address minter_, uint256 collateral_) internal returns (uint256 lastUpdateTimestamp_) {
        uint256[] memory retrievalIds = new uint256[](0);

        return _updateCollateral(minter_, collateral_, retrievalIds);
    }

    function _updateCollateral(
        address minter_,
        uint256 collateral_,
        uint256[] memory retrievalIds
    ) internal returns (uint256 lastUpdateTimestamp_) {
        uint256 signatureTimestamp = block.timestamp;

        address[] memory validators = new address[](1);
        validators[0] = _validators[0];

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_protocol),
            minter_,
            collateral_,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validatorKeys[0]
        );

        vm.warp(block.timestamp + 1 hours);

        vm.prank(minter_);
        _protocol.updateCollateral(collateral_, retrievalIds, bytes32(0), validators, timestamps, signatures);

        return signatureTimestamp;
    }

    function _mintM(address minter_, uint256 mintAmount_, address recipient_) internal {
        vm.prank(minter_);
        uint256 mintId = _protocol.proposeMint(mintAmount_, recipient_);

        vm.warp(block.timestamp + _mintDelay + 1 hours); // 1 hour after the mint delay, the minter mints M.

        vm.prank(minter_);
        _protocol.mintM(mintId);
    }

    function _batchMintM(
        address[] memory minters_,
        uint256[] memory mintAmounts_,
        address[] memory recipients_
    ) internal {
        uint256[] memory mintIds = new uint256[](minters_.length);
        for (uint256 i; i < mintAmounts_.length; ++i) {
            vm.prank(minters_[i]);
            mintIds[i] = _protocol.proposeMint(mintAmounts_[i], recipients_[i]);
        }

        vm.warp(block.timestamp + _mintDelay + 1 hours); // 1 hour after the mint delay, the minter mints M.

        for (uint256 i; i < mintAmounts_.length; ++i) {
            vm.prank(minters_[i]);
            _protocol.mintM(mintIds[i]);
        }
    }
}
