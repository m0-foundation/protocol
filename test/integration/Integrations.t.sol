// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";

import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";

import { IntegrationBaseSetup } from "./IntegrationBaseSetup.t.sol";

// TODO: Check mints to Vault.

contract IntegrationTests is IntegrationBaseSetup {
    function test_story1() external {
        // Set test specific parameters
        _mintDelay = 12 hours;
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, _mintDelay);
        _registrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, uint256(0));

        _minterGateway.updateIndex();

        // Since the contracts ae deployed at the same time, these values are the same..
        uint256 latestMinterGatewayUpdateTimestamp_ = block.timestamp;
        uint256 latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterRateModel.baseRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000000000000);
        assertEq(_minterGateway.currentIndex(), 1_000000000000);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_earnerRateModel.baseRate(), 1_000);
        assertEq(_mToken.rateModel(), address(_earnerRateModel));
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + 2 hours); // 2 hours after deploy, minter collects signatures.

        uint256 collateral = 1_000_000e6;
        uint256 mintAmount = 500_000e6;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 signatureTimestamp = block.timestamp;

        address[] memory validators = new address[](1);
        validators[0] = _validators[0];

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            address(_minterGateway),
            _minters[0],
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validatorKeys[0]
        );

        vm.warp(block.timestamp + 1 hours); // 1 hour after collecting signatures, minter updateCollateral is mined.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000000000000);
        assertEq(_minterGateway.currentIndex(), 1_000034247161);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        _minterGateway.activateMinter(_minters[0]);

        assertEq(_minterGateway.isActiveMinter(_minters[0]), true);

        vm.prank(_minters[0]);
        _minterGateway.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        // Both timestamps are updated since updateIndex gets called on the minterGateway, and thus on the mToken.
        latestMinterGatewayUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000034247161);
        assertEq(_minterGateway.currentIndex(), 1_000034247161);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        vm.prank(_alice);
        _mToken.startEarning();

        // No index values are updated since nothing relevant changed.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000034247161);
        assertEq(_minterGateway.currentIndex(), 1_000045663141);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        uint256 mintId = _minterGateway.proposeMint(mintAmount, _alice);

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000034247161);
        assertEq(_minterGateway.currentIndex(), 1_000045663141);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + _mintDelay + 1 hours); // 1 hour after the mint delay, the minter mints M.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000034247161);
        assertEq(_minterGateway.currentIndex(), 1_000194082756);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        _minterGateway.mintM(mintId);

        // Both timestamps are updated since updateIndex gets called on the minterGateway, and thus on the mToken.
        latestMinterGatewayUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000194082756);
        assertEq(_minterGateway.currentIndex(), 1_000194082756);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 500_000_000001); // ~500k
        assertEq(_mToken.balanceOf(_alice), 500_000_000000); // 500k
        assertEq(_mToken.balanceOf(_vault), 1);

        vm.warp(block.timestamp + 356 days); // 1 year later, Alice transfers all all her M to Bob, who is not earning.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000194082756);
        assertEq(_minterGateway.currentIndex(), 1_102663162403);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_000000000000);
        assertEq(_mToken.currentIndex(), 1_102449196025);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 551_224_598014); // ~500k with 10% APY compounded continuously.
        assertEq(_mToken.balanceOf(_alice), 551_224_598012); // ~500k with 10% APY compounded continuously.
        assertEq(_mToken.balanceOf(_vault), 1); // Still 0 since no call to `_minterGateway.updateIndex()`.

        uint256 transferAmount_ = _mToken.balanceOf(_alice);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        // Only mToken is updated since mToken does not cause state changes in MinterGateway.
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_000194082756);
        assertEq(_minterGateway.currentIndex(), 1_102663162403);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102449196025);
        assertEq(_mToken.currentIndex(), 1_102449196025);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 551_224_598014);
        assertEq(_mToken.balanceOf(_alice), 0); // Rounding error left over.
        assertEq(_mToken.balanceOf(_bob), 551_224_598012);
        assertEq(_mToken.balanceOf(_vault), 1); // No change since no call to `_minterGateway.updateIndex()`.

        vm.warp(block.timestamp + 1 hours); // 1 hour later, someone updates the indices.

        uint256 excessOwedM = _minterGateway.excessOwedM();
        assertEq(excessOwedM, 6_292555);

        _minterGateway.updateIndex();

        // Both timestamps are updated since updateIndex gets called on the minterGateway, and thus on the mToken.
        latestMinterGatewayUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_102675749954);
        assertEq(_minterGateway.currentIndex(), 1_102675749954);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102461781133);
        assertEq(_mToken.currentIndex(), 1_102461781133);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 551_230_890568);
        assertEq(_mToken.balanceOf(_bob), 551_224_598012); // Bob is not earning, so no change.
        assertEq(_mToken.balanceOf(_vault), 6_292556); // Excess active owed M is distributed to vault.

        excessOwedM = _minterGateway.excessOwedM();
        assertEq(excessOwedM, 0);

        vm.warp(block.timestamp + 1 days); // 1 day later, bob starts earning.

        vm.prank(_bob);
        _mToken.startEarning();

        // Only mToken is updated since mToken does not cause state changes in MinterGateway.
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_102675749954);
        assertEq(_minterGateway.currentIndex(), 1_102977894285);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102763866834);
        assertEq(_mToken.currentIndex(), 1_102763866834);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 551_381_933418);
        assertEq(_mToken.balanceOf(_bob), 551_224_598011);
        assertEq(_mToken.balanceOf(_vault), 6_292556); // No change since no call to `_minterGateway.updateIndex()`.

        vm.warp(block.timestamp + 30 days); // 30 days later, the unresponsive minter is deactivated.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_102675749954);
        assertEq(_minterGateway.currentIndex(), 1_112080824074);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102763866834);
        assertEq(_mToken.currentIndex(), 1_111865030243);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 555_932_515123);
        assertEq(_mToken.balanceOf(_bob), 555_773_881219);
        assertEq(_mToken.balanceOf(_vault), 6_292556); // No change since no call to `_minterGateway.updateIndex()`.

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minters[0]);

        _minterGateway.deactivateMinter(_minters[0]);

        // Both timestamps are updated since updateIndex gets called on the minterGateway, and thus on the mToken.
        latestMinterGatewayUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_112080824074);
        assertEq(_minterGateway.currentIndex(), 1_112080824074);
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0); // Dropped to zero due to drastic change in utilization.
        assertEq(_mToken.latestIndex(), 1_111865030243);
        assertEq(_mToken.currentIndex(), 1_111865030243);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 0);
        assertEq(_minterGateway.inactiveOwedMOf(_minters[0]), 555_932_515123);
        assertEq(_mToken.balanceOf(_bob), 555_773_881219);

        assertEq(_mToken.balanceOf(_vault), 158633904); // Delta is distributed to vault.

        // Main invariant of the system: totalActiveOwedM >= totalSupply of M Token.
        assertEq(
            _mToken.balanceOf(_bob) + _mToken.balanceOf(_vault),
            _minterGateway.totalActiveOwedM() + _minterGateway.totalInactiveOwedM()
        );

        vm.warp(block.timestamp + 30 days); // 30 more days pass without any changes to the system.

        assertEq(_minterGateway.minterRate(), 1_000);
        assertEq(_minterGateway.latestIndex(), 1_112080824074);
        assertEq(_minterGateway.currentIndex(), 1_121258880780); // Incased due to nonzero minter rate.
        assertEq(_minterGateway.latestUpdateTimestamp(), latestMinterGatewayUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_111865030243);
        assertEq(_mToken.currentIndex(), 1_111865030243); // No change due to no earner rate in last 30 days.
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_minterGateway.activeOwedMOf(_minters[0]), 0);
        assertEq(_minterGateway.inactiveOwedMOf(_minters[0]), 555_932_515123);
        assertEq(_mToken.balanceOf(_bob), 555_773_881219); // No change due to no earner rate in last 30 days.
        assertEq(_mToken.balanceOf(_vault), 158633904); // No change since conditions did not change.
    }
}
