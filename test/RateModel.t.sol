// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { StableEarnerRateModel } from "../src/rateModels/StableEarnerRateModel.sol";

import { MockMinterGateway } from "./utils/Mocks.sol";

contract ContinuousIndexingMathTests is Test {
    StableEarnerRateModel internal stableModel;
    MockMinterGateway internal minterGateway;

    function setUp() external {
        minterGateway = new MockMinterGateway();
        minterGateway.setTtgRegistrar(address(1));
        minterGateway.setMToken(address(1));

        stableModel = new StableEarnerRateModel(address(minterGateway));
    }

    function test_stableModel_getSafeEarnerRate() external {
        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 0,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            type(uint32).max
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            1097245 // 10,972.45%
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 500_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            1991 // 19.91%
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 999_999,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            999 // 9.99%
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            1000 // 9.99%
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 500_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            0 // TODO: Ideally we give 5%, but for now this test returns 0.
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_091, // Lowest before result is 0
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            0 // TODO: Ideally we give 0.01%/, but for now this test returns 0.
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            0 // 0%
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 0,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            0 // 0%
        );
    }
}
