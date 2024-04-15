// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../lib/forge-std/src/Test.sol";

import { EarnerRateModel } from "../src/rateModels/EarnerRateModel.sol";
import { MinterRateModel } from "../src/rateModels/MinterRateModel.sol";

import { MockMinterGateway, MockTTGRegistrar } from "./utils/Mocks.sol";

contract RateModelTests is Test {
    EarnerRateModel internal _earnerRateModel;
    MinterRateModel internal _minterModel;
    MockMinterGateway internal _minterGateway;
    MockTTGRegistrar internal _ttgRegistrar;

    function setUp() external {
        _minterGateway = new MockMinterGateway();
        _minterGateway.setTtgRegistrar(address(1));
        _minterGateway.setMToken(address(1));

        _earnerRateModel = new EarnerRateModel(address(_minterGateway));

        _ttgRegistrar = new MockTTGRegistrar();
        _minterModel = new MinterRateModel(address(_ttgRegistrar));
    }

    function test_earnerRateModel_getSafeEarnerRate() external {
        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 0,
                minterRate_: 1_000
            }),
            type(uint32).max
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1,
                minterRate_: 1_000
            }),
            1097245 // 10,972.45%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 500_000,
                minterRate_: 1_000
            }),
            1991 // 19.91%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 999_999,
                minterRate_: 1_000
            }),
            1000 // 10.00%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            1000 // ~10.00%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 500_000,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            500
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_091, // Lowest before result is 0
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            1
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            0 // 0%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 0,
                totalEarningSupply_: 1_000_000,
                minterRate_: 1_000
            }),
            0 // 0%
        );

        assertEq(
            _earnerRateModel.getSafeEarnerRate({
                totalActiveOwedM_: 1_000_000,
                totalEarningSupply_: 0,
                minterRate_: 0
            }),
            0 // 0%
        );
    }

    function test_minterModel_maxMinterRate() external {
        _ttgRegistrar.updateConfig("base_minter_rate", 100_000);
        assertEq(_minterModel.rate(), _minterModel.MAX_MINTER_RATE());
        assertEq(_minterModel.MAX_MINTER_RATE(), 40_000);

        _ttgRegistrar.updateConfig("base_minter_rate", 20_000);
        assertEq(_minterModel.rate(), 20_000);
    }
}
