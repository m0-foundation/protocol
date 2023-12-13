// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { ProtocolHarness } from "./util/ProtocolHarness.sol";
import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";
import { IRateModel } from "../../src/interfaces/IRateModel.sol";
import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

contract ProtocolTest is Test {
    ProtocolHarness _protocol;

    address internal _protocolAddress;
    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _mTokenAddress = makeAddr("mToken");
    address internal _vaultAddress = makeAddr("vault");
    address internal _minterRateModelAddress = makeAddr("minterRateModel");

    address internal _aliceAddress = makeAddr("alice");
    address internal _bobAddress = makeAddr("bob");
    address internal _charlieAddress = makeAddr("charlie");
    address internal _davidAddress = makeAddr("david");

    uint256 internal _blockTimestamp = 1_000_000_000;

    function setUp() public {
        // vault
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.vault.selector),
            abi.encode(_vaultAddress)
        );

        vm.warp(_blockTimestamp);

        _protocol = new ProtocolHarness(_spogRegistrarAddress, _mTokenAddress);
        _protocolAddress = address(_protocol);
    }

    function test_setUp() public {
        assertEq(_spogRegistrarAddress, _protocol.spogRegistrar(), "Setup spogRegistrar address failed");
        assertEq(_vaultAddress, _protocol.spogVault(), "Setup vault failed");
        assertEq(_mTokenAddress, _protocol.mToken(), "Setup mToken address failed");
    }

    /******************************************************************************************************************\
    |                                           Internal View/Pure Functions                                           |
    \******************************************************************************************************************/

    /**
     * Test with a global update collateral interval of '0' (zero).
     * Is that a valid case?
     */
    function test__getPenaltyBaseAndTimeForMissedCollateralUpdates_zeroUpdateCollateral() public {
        uint256 activeOwedM = 100_038_363_521_300_872_800; // see test_activeOwedMOf_SevenDaysVanillaIndex
        _protocol.setter_principalOfActiveOwedM(_aliceAddress, 100 * 1e18);
        _protocol.setter_latestIndex(1 * 1e18);
        _protocol.setter_latestUpdateTimestamp(7 days);
        _protocol.setter_latestRate(200);

        vm.warp(14 days);

        // Set a global '0' collateral update.
        // Where is this initially set?
        _setValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 0);

        _protocol.setter_lastUpdateInterval(_aliceAddress, 1 days); // minter update interval = 1 day
        _protocol.setter_lastUpdateTimestamp(_aliceAddress, 12 days); // last update on day 13
        _protocol.setter_penalizedUntilTimestamp(_aliceAddress, 12 days); // last penalized on day 13

        // if updateInterval_ == 0 --> max(lastUpdate_, penalizedUntil_)
        // if (lastUpdate_ + updateInterval_) > block.timestamp --> return (0, lastUpdate_)
        // if (penalizedUntil_ + updateInterval_) > block.timestamp --> return (0, penalizedUntil_)

        // Fail with division by zero
        _protocol.external_getPenaltyBaseAndTimeForMissedCollateralUpdates(_aliceAddress);
    }

    /******************************************************************************************************************\
    |                                           Test Helper                                         |
    \******************************************************************************************************************/

    function _setValue(bytes32 name_, uint256 value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        );
    }

    function _setValue(bytes32 name_, address value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        );
    }
}
