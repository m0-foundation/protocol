// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { ContinuousIndexingHarness } from "./util/ContinuousIndexingHarness.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IRateModel } from "../../src/interfaces/IRateModel.sol";
import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";
//import { IEarnerRateModel } from "../../src/interfaces/IEarnerRateModel.sol";
//import { IMinterRateModel } from "../../src/interfaces/IMinterRateModel.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";


contract ContinousIndexingTest is Test {

    ContinuousIndexingHarness internal _continuousIndexing; 
    uint256 internal _rate = 100; // 10% (1000 = 100%)
    uint256 internal _timestamp = 1_000_000_000; 
    uint256 internal _index = 1_000_000_000_000_000_000; // 1 * scale

    function setUp() public {
        vm.warp(_timestamp);
        _continuousIndexing = new ContinuousIndexingHarness();
        _continuousIndexing.setter_rate(_rate);
    }

    function test_setUp() public {
        assertEq(_index, _continuousIndexing.latestIndex(), "Setup latest index failed");
        assertEq(_rate, _continuousIndexing.getter_rate(), "Setup rate failed");
        assertEq(_timestamp, _continuousIndexing.latestUpdateTimestamp(), "Setup update timestamp failed");
    }


    /******************************************************************************************************************\
    |                                       External/Public Interactive Functions                                        |
    \******************************************************************************************************************/


    function test_updateIndex() public {

    }

    /******************************************************************************************************************\
    |                                       External/Public View/Pure Functions                                        |
    \******************************************************************************************************************/

    function test_currentIndex_OneYearVanillaIndex() public {
        // Interest compounding over one year
        _continuousIndexing.setter_latestIndex(1 * 1e18); // 1
        _continuousIndexing.setter_latestUpdateTimestamp(0); // converted into seconds
        _continuousIndexing.setter_latestRate(1000); // 10%    
        vm.warp(365 days); // one year later

        assertEq(1_105_170_833_333_333_332, _continuousIndexing.currentIndex());
    }

    function test_currentIndex_TwoDaysVanillaIndex() public {
        // Interest compounding over two days
        _continuousIndexing.setter_latestIndex(1 * 1e18); // 1
        _continuousIndexing.setter_latestUpdateTimestamp(12 days); // converted into seconds
        _continuousIndexing.setter_latestRate(200); // 10%
        vm.warp(14 days); // 2 days later

        assertEq(1_000_109_595_046_194_216, _continuousIndexing.currentIndex());
    }

    function test_currentIndex_SevenDaysVanillaIndex() public {
        // Interest compounding over one year
        _continuousIndexing.setter_latestIndex(1 * 1e18); // 1
        _continuousIndexing.setter_latestUpdateTimestamp(7 days); // converted into seconds
        _continuousIndexing.setter_latestRate(200); // 10%    
        vm.warp(14 days); // 7 days later

        assertEq(1_000_383_635_213_008_728, _continuousIndexing.currentIndex());
    }

    function test_latestIndex() public {
        assertEq(_index, _continuousIndexing.latestIndex());
    }

    function test_latestUpdateTimestamp() public {
        assertEq(_timestamp, _continuousIndexing.latestUpdateTimestamp());
    }

    /******************************************************************************************************************\
    |                                          Internal Interactive Functions                                          |
    \******************************************************************************************************************/

    function test_getPresentAmountAndUpdateIndex() public {

    }

    function test_getPrincipalAmountAndUpdateIndex() public {

    }

        /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    function test_getPresentAmount() public {
        assertEq(2_000_000_000_000_000_000, _continuousIndexing.external_getPresentAmount(1_000_000_000_000_000_000, 2_000_000_000_000_000_000)); 
        assertEq(1_105_170_833_333_333_332, _continuousIndexing.external_getPresentAmount(1_000_000_000_000_000_000, 1_105_170_833_333_333_332)); 
    }

    function test_getPrincipalAmount() public {

    }


}
