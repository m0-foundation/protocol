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
                totalEarningSupply_: 500_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            1991
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 999_999,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            999
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            999
        );

        assertEq(
            stableModel.getSafeEarnerRate({
                totalActiveOwedM_: 500_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000,
                confidenceInterval_: 30 days
            }),
            500
        );
    }
}
