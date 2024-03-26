// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { stdError, Test } from "../../lib/forge-std/src/Test.sol";

import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";

import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

import { IntegrationBaseSetup } from "../integration/IntegrationBaseSetup.t.sol";

contract FuzzTests is IntegrationBaseSetup {
    function testFuzz_earnerRateGreaterThanMinterRate(
        uint256 minterRate,
        uint256 earnerRate,
        uint256 mintAmountToEarner,
        uint256 mintAmountToNonEarner,
        uint256 timeElapsed
    ) external {
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, uint256(0));
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 365 days);
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, uint256(0));

        minterRate = bound(minterRate, 100, 40000); // [0.1%, 400%] in basis points
        earnerRate = bound(earnerRate, minterRate, 40000); // [minterRate, 400%] in basis points
        mintAmountToEarner = bound(mintAmountToEarner, 1_000e6, 1_000e15);
        mintAmountToNonEarner = bound(mintAmountToNonEarner, 1_000e6, 1_000e15);
        timeElapsed = bound(timeElapsed, 10, 10 days); // [10, 10 days]

        _registrar.updateConfig(BASE_MINTER_RATE, minterRate);
        _registrar.updateConfig(MAX_EARNER_RATE, earnerRate);

        vm.prank(_mHolders[0]);
        _mToken.startEarning();

        _minterGateway.activateMinter(_minters[0]);

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minters[0]);
        _minterGateway.updateCollateral(
            2 * (mintAmountToEarner + mintAmountToNonEarner),
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );
        vm.prank(_minters[0]);
        uint256 mintId1 = _minterGateway.proposeMint(mintAmountToEarner, _mHolders[0]);

        vm.prank(_minters[0]);
        _minterGateway.mintM(mintId1);

        vm.prank(_minters[0]);
        uint256 mintId2 = _minterGateway.proposeMint(mintAmountToNonEarner, _mHolders[1]);

        vm.prank(_minters[0]);
        _minterGateway.mintM(mintId2);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        _checkMainInvariant();
    }

    function testFuzz_deactivateMinter_earnerRateGreaterThanMinterRate(
        uint256 minterRate,
        uint256 earnerRate,
        uint256 minter1Amount,
        uint256 minter2Amount,
        uint256 timeElapsed
    ) external {
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, uint256(0));
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 365 days);
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, uint256(0));

        minterRate = bound(minterRate, 100, 40000); // [0.1%, 400%] in basis points
        earnerRate = bound(earnerRate, minterRate, 40000); // [minterRate, 400%] in basis points
        minter1Amount = bound(minter1Amount, 1_000e6, 1_000e15);
        minter2Amount = bound(minter2Amount, 1_000e6, 1_000e15);
        timeElapsed = bound(timeElapsed, 10, 10 days); // [10, 10 days]

        _registrar.updateConfig(BASE_MINTER_RATE, minterRate);
        _registrar.updateConfig(MAX_EARNER_RATE, earnerRate);

        vm.prank(_mHolders[0]);
        _mToken.startEarning();

        _minterGateway.activateMinter(_minters[0]);
        _minterGateway.activateMinter(_minters[1]);

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minters[0]);
        _minterGateway.updateCollateral(
            2 * minter1Amount,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        vm.prank(_minters[1]);
        _minterGateway.updateCollateral(
            2 * minter2Amount,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        vm.prank(_minters[0]);
        uint256 mintId1 = _minterGateway.proposeMint(minter1Amount, _mHolders[0]);

        vm.prank(_minters[1]);
        uint256 mintId2 = _minterGateway.proposeMint(minter2Amount, _mHolders[1]);

        vm.prank(_minters[0]);
        _minterGateway.mintM(mintId1);

        vm.prank(_minters[1]);
        _minterGateway.mintM(mintId2);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minters[0]);
        IMinterGateway(_minterGateway).deactivateMinter(_minters[0]);

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        _checkMainInvariant();
    }

    function test_deactivateMinter_rateStabilityTest() external {
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, uint256(0));
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 365 days);
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, uint256(0));

        uint256 minterRate = 4001;
        uint256 earnerRate = 4001;
        uint256 minter1Amount = 999999999999999997;
        uint256 minter2Amount = 999999999000000005;
        uint256 timeElapsed1 = 134395;
        uint256 timeElapsed2 = 10;

        _registrar.updateConfig(BASE_MINTER_RATE, minterRate);
        _registrar.updateConfig(MAX_EARNER_RATE, earnerRate);

        vm.prank(_mHolders[0]);
        _mToken.startEarning();

        _minterGateway.activateMinter(_minters[0]);
        _minterGateway.activateMinter(_minters[1]);

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(_minters[0]);
        _minterGateway.updateCollateral(
            2 * minter1Amount,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        vm.prank(_minters[1]);
        _minterGateway.updateCollateral(
            2 * minter2Amount,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        vm.prank(_minters[0]);
        uint256 mintId1 = _minterGateway.proposeMint(minter1Amount, _mHolders[0]);

        vm.prank(_minters[1]);
        uint256 mintId2 = _minterGateway.proposeMint(minter2Amount, _mHolders[1]);

        vm.prank(_minters[0]);
        _minterGateway.mintM(mintId1);

        vm.prank(_minters[1]);
        _minterGateway.mintM(mintId2);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed1);

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, _minters[0]);
        IMinterGateway(_minterGateway).deactivateMinter(_minters[0]);

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        vm.warp(vm.getBlockTimestamp() + timeElapsed1);

        _checkMainInvariant();

        vm.warp(vm.getBlockTimestamp() + timeElapsed2);

        _checkMainInvariant();
    }

    function _checkMainInvariant() internal {
        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        _minterGateway.updateIndex();

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );
    }
}
