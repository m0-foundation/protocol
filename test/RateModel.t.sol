// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { StableEarnerRateModel } from "../src/rateModels/StableEarnerRateModel.sol";

import { MockMinterGateway } from "./utils/Mocks.sol";

contract RateModelTests is Test {
    StableEarnerRateModel internal _stableModel;
    MockMinterGateway internal _minterGateway;

    function setUp() external {
        _minterGateway = new MockMinterGateway();
        _minterGateway.setTtgRegistrar(address(1));
        _minterGateway.setMToken(address(1));

        _stableModel = new StableEarnerRateModel(address(_minterGateway));
    }

    function test_stableModel_getSafeEarnerRate() external {
        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 0,
                minterRate_: 1_000
            }),
            type(uint32).max
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1,
                minterRate_: 1_000
            }),
            1097245 // 10,972.45%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 500_000,
                minterRate_: 1_000
            }),
            1991 // 19.91%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 999_999,
                minterRate_: 1_000
            }),
            1000 // 10.00%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            1000 // ~10.00%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 500_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            500
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_091, // Lowest before result is 0
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            1
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            0 // 0%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 0,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            0 // 0%
        );

        assertEq(
            _stableModel.getSafeEarnerRate({ totalActiveOwedM_: 1_000_000, totalEarningSupply_: 0, minterRate_: 0 }),
            0 // 0%
        );
    }
}
