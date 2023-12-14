// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../../lib/forge-std/src/Test.sol";
import { SPOGRegistrarReader } from "../../../src/libs/SPOGRegistrarReader.sol";
import { ISPOGRegistrar } from "../../../src/interfaces/ISPOGRegistrar.sol";


contract SPOGRegistrarReaderTest is Test {

    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");


    function setUp() public {
            vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector),
            abi.encode()
        ); 

        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector),
            abi.encode(false)
        ); 
    }

    function test_getBaseEarnerRate() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.BASE_EARNER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getBaseEarnerRate(_spogRegistrarAddress));
    }

    function test_getBaseMinterRate() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.BASE_MINTER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getBaseMinterRate(_spogRegistrarAddress));
    }

    function test_getEarnerRateModel() public {
        address rateModel = makeAddr("rateModel");
        _setSPOGRegistrarValue(SPOGRegistrarReader.EARNER_RATE_MODEL, rateModel);

        assertEq(rateModel, SPOGRegistrarReader.getEarnerRateModel(_spogRegistrarAddress));
    }

    function test_getMintDelay() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.MINT_DELAY, 123);

        assertEq(123, SPOGRegistrarReader.getMintDelay(_spogRegistrarAddress));
    }

    function test_getMinterFreezeTime() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.MINTER_FREEZE_TIME, 123);

        assertEq(123, SPOGRegistrarReader.getMinterFreezeTime(_spogRegistrarAddress));
    }

    function test_getMinterRate() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.MINTER_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getMinterRate(_spogRegistrarAddress));
    }

    function test_getMinterRateModel() public {

        address rateModel = makeAddr("rateModel");
        _setSPOGRegistrarValue(SPOGRegistrarReader.MINTER_RATE_MODEL, rateModel);

        assertEq(rateModel, SPOGRegistrarReader.getMinterRateModel(_spogRegistrarAddress));
    }

    function test_getMintTTL() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.MINT_TTL, 123);

        assertEq(123, SPOGRegistrarReader.getMintTTL(_spogRegistrarAddress));
    }

    function test_getUpdateCollateralInterval() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 123);

        assertEq(123, SPOGRegistrarReader.getUpdateCollateralInterval(_spogRegistrarAddress));
    }

    // TODO #1
    function test_getUpdateCollateralValidatorThreshold() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD, 123);

        assertEq(123, SPOGRegistrarReader.getUpdateCollateralValidatorThreshold(_spogRegistrarAddress));
    }

    function test_isApprovedEarner_negative() public {
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedEarner(_spogRegistrarAddress, account));
    }

    function test_isApprovedEarner_positive() public {
        address account = makeAddr("account");
        _addAddressToSPOGList(SPOGRegistrarReader.EARNERS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedEarner(_spogRegistrarAddress, account));
    }

    function test_isEarnersListIgnored_negative() public {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.EARNERS_LIST_IGNORED),
            abi.encode(bytes32(0))
        ); 

        assertFalse(SPOGRegistrarReader.isEarnersListIgnored(_spogRegistrarAddress));
    }

    function test_isEarnersListIgnored_positive() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.EARNERS_LIST_IGNORED, 1);

        assertTrue(SPOGRegistrarReader.isEarnersListIgnored(_spogRegistrarAddress));
    }

    function test_isApprovedMinter_negative() public {
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedMinter(_spogRegistrarAddress, account));
    }

    function test_isApprovedMinter_positive() public {
        address account = makeAddr("account");
        _addAddressToSPOGList(SPOGRegistrarReader.MINTERS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedMinter(_spogRegistrarAddress, account));
    }

    function test_isApprovedValidator_negative() public {
        address account = makeAddr("account");

        assertFalse(SPOGRegistrarReader.isApprovedValidator(_spogRegistrarAddress, account));
    }

    function test_isApprovedValidator_positive() public {
        address account = makeAddr("account");
        _addAddressToSPOGList(SPOGRegistrarReader.VALIDATORS_LIST, account);

        assertTrue(SPOGRegistrarReader.isApprovedValidator(_spogRegistrarAddress, account));
    }

    function test_getPenaltyRate() public {
        _setSPOGRegistrarValue(SPOGRegistrarReader.PENALTY_RATE, 123);

        assertEq(123, SPOGRegistrarReader.getPenaltyRate(_spogRegistrarAddress));
    }

    function test_getVault() public {
        address vaultAddress_ = makeAddr("vault");
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.vault.selector),
            abi.encode(vaultAddress_ )
        ); 

        assertEq(vaultAddress_ , SPOGRegistrarReader.getVault(_spogRegistrarAddress));
    }

    // function test_toAddress() public {
    // }

    // function test_toBytes32() public {
    // }

    // Helper
    function _setSPOGRegistrarValue(bytes32 name_, uint256 value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        ); 
    }

    function _setSPOGRegistrarValue(bytes32 name_, address value_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        ); 
    }

    function _addAddressToSPOGList(bytes32 list_, address account_) private {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector, list_, account_),
            abi.encode(true)
        ); 
    }

}
