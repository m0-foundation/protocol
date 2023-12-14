// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import { console2, stdError, Test, Vm } from "../../lib/forge-std/src/Test.sol";
import { ContractHelper } from "../../lib/common/src/ContractHelper.sol";
import { ProtocolHarness } from "./util/ProtocolHarness.sol";
import { MTokenHarness } from "./util/MTokenHarness.sol";
import { DigestHelper } from "../utils/DigestHelper.sol";


import { ISPOGRegistrar } from "../../src/interfaces/ISPOGRegistrar.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import { EarnerRateModel } from "../../src/EarnerRateModel.sol";
import { MinterRateModel } from "../../src/MinterRateModel.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IContinuousIndexing } from "../../src/interfaces/IContinuousIndexing.sol";
import { IRateModel } from "../../src/interfaces/IRateModel.sol";
import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

abstract contract ScenarioTest is Test {
    ProtocolHarness internal _protocol;
    MTokenHarness internal _mToken;
    EarnerRateModel internal _earnerRateModel;
    MinterRateModel internal _minterRateModel;

    address internal _spogRegistrarAddress = makeAddr("spogRegistrar");
    address internal _vaultAddress = makeAddr("vault");

    // Time tracking
    uint256 internal _startTimestamp = 1672527600; // 2023-01-01 00:00:00
    uint256 internal _lastTimestamp = _startTimestamp;
    uint256 internal _currentTimestamp = _startTimestamp;
    uint256[100] public t;

    // M Holders (all earners)
    Account internal _alice = makeAccount("alice");
    Account internal _bob = makeAccount("bob");
    Account internal _charlie = makeAccount("charlie");
    Account internal _david = makeAccount("david");
    Account[] internal _mHolders;

    // Minters
    Account internal _michael = makeAccount("michael");
    Account internal _matthew = makeAccount("matthew");
    Account internal _maria = makeAccount("maria");
    Account internal _monica = makeAccount("monica");
    Account[] internal _minters;

    // Validators
    Account internal _victor = makeAccount("victor");
    Account internal _vincent = makeAccount("vincent");
    Account internal _valerie = makeAccount("valerie");
    Account internal _veronica = makeAccount("veronica");
    Account[] internal _validators;


    function _setUp() internal {
        // SPOG Values by default not set
        vm.mockCall(_spogRegistrarAddress, abi.encodeWithSelector(ISPOGRegistrar.get.selector), abi.encode()); 
        // SPOG Lists by default do not contain anything
        vm.mockCall(_spogRegistrarAddress, abi.encodeWithSelector(ISPOGRegistrar.listContains.selector), abi.encode(false)); 
        // special treatment for this value :/
        vm.mockCall(_spogRegistrarAddress, abi.encodeWithSelector(ISPOGRegistrar.get.selector, SPOGRegistrarReader.EARNERS_LIST_IGNORED), abi.encode(bytes32(0))); 
        // Setup Vault
        vm.mockCall(_spogRegistrarAddress, abi.encodeWithSelector(ISPOGRegistrar.vault.selector), abi.encode(_vaultAddress)); 

        // Set start timestamp
        vm.warp(_startTimestamp);
        t[0] = _startTimestamp;

        // SPOG Values

        _spogSetValue(SPOGRegistrarReader.BASE_EARNER_RATE, 1_000); // 10%
        _spogSetValue(SPOGRegistrarReader.BASE_MINTER_RATE, 1_000);
         // 10%
        _spogSetValue(SPOGRegistrarReader.PENALTY_RATE, 500); // 5%
        _spogSetValue(SPOGRegistrarReader.MINT_DELAY, 3 hours);
        _spogSetValue(SPOGRegistrarReader.MINT_TTL, 24 hours);
        _spogSetValue(SPOGRegistrarReader.MINT_RATIO, 9_000); // 90%
        _spogSetValue(SPOGRegistrarReader.MINTER_FREEZE_TIME, 7 days);
        _spogSetValue(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD, 1); // one signature needed
        _spogSetValue(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 24 hours);

        // Actors
        _spogAddAccount(SPOGRegistrarReader.EARNERS_LIST, _alice.addr);
        _spogAddAccount(SPOGRegistrarReader.EARNERS_LIST, _bob.addr);
        _spogAddAccount(SPOGRegistrarReader.EARNERS_LIST, _charlie.addr);
        _spogAddAccount(SPOGRegistrarReader.EARNERS_LIST, _david.addr);
        _mHolders.push(_alice);
        _mHolders.push(_bob);
        _mHolders.push(_charlie);
        _mHolders.push(_david);

        _spogAddAccount(SPOGRegistrarReader.MINTERS_LIST, _michael.addr);
        _spogAddAccount(SPOGRegistrarReader.MINTERS_LIST, _matthew.addr);
        _spogAddAccount(SPOGRegistrarReader.MINTERS_LIST, _maria.addr);
        _spogAddAccount(SPOGRegistrarReader.MINTERS_LIST, _monica.addr);
        _minters.push(_michael);
        _minters.push(_matthew);
        _minters.push(_maria);
        _minters.push(_monica);

        _spogAddAccount(SPOGRegistrarReader.VALIDATORS_LIST, _victor.addr);
        _spogAddAccount(SPOGRegistrarReader.VALIDATORS_LIST, _vincent.addr);
        _spogAddAccount(SPOGRegistrarReader.VALIDATORS_LIST, _valerie.addr);
        _spogAddAccount(SPOGRegistrarReader.VALIDATORS_LIST, _veronica.addr);
        _validators.push(_victor);
        _validators.push(_vincent);
        _validators.push(_valerie);
        _validators.push(_veronica);

        // Objects
        // "forecast" which address will be used for the deployments, 
        // because we have a cyclic dependency between protocol and mToken
        address mTokenAddress_ = ContractHelper.getContractFrom(address(this), 1);
        address protocolAddress_ = ContractHelper.getContractFrom(address(this), 2);

        _mToken = new MTokenHarness(_spogRegistrarAddress, protocolAddress_);
        _protocol = new ProtocolHarness(_spogRegistrarAddress, mTokenAddress_);
        _earnerRateModel = new EarnerRateModel(protocolAddress_);
        _minterRateModel = new MinterRateModel(_spogRegistrarAddress);

        // Rate models addresses need to be set as config parameters
        _spogSetValue(SPOGRegistrarReader.EARNER_RATE_MODEL, address(_earnerRateModel));
        _spogSetValue(SPOGRegistrarReader.MINTER_RATE_MODEL, address(_minterRateModel));

        // Initialize values for compounding
        //_protocol.updateIndex();
    }


    function test_setUp() virtual public {
        // assertEq(0, _protocol.minterRate(), "Setup protocol minterRate failed");
        // assertEq(1e18, _protocol.latestIndex(), "Setup protocol lastIndex failed");
        // assertEq(1e18, _protocol.currentIndex(), "Setup protocol minterRate failed");
        // assertEq(_startTimestamp, _protocol.latestUpdateTimestamp(), "Setup protocol latestUpdateTimestamp failed");

        // assertEq(0, _mToken.earnerRate(), "Setup mToken earnerRate failed");
        // assertEq(1e18, _mToken.latestIndex(), "Setup mToken lastIndex failed");
        // assertEq(1e18, _mToken.currentIndex(), "Setup mToken minterRate failed");
        // assertEq(_startTimestamp, _mToken.latestUpdateTimestamp(), "Setup mToken latestUpdateTimestamp failed");
    }

    // Signature Helper
    function _createUpdateCollateralSignature(
        address minter,
        uint256 collateral,
        uint256[] memory retrievalIds,
        bytes32 metadataHash,
        uint256 timestamp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = DigestHelper.getUpdateCollateralDigest(
            address(_protocol),
            minter,
            collateral,
            retrievalIds,
            metadataHash,
            timestamp
        );

        return _createSignature(digest, privateKey);
    }

    function _createSignature(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    // Compunding Interest Helper
    function assertProtocolIndexing(
        uint256 expectedRate_, 
        uint256 expectedLatestIndex_,
        uint256 expectedCurrentIndex, 
        uint256 expectedUpdateTimestamp_
    ) internal {
        assertEq(expectedRate_, _protocol.minterRate(), "Protocol rate is unexpected");
        assertEq(expectedLatestIndex_, _protocol.latestIndex(), "Protocol latestIndex is unexpected");
        assertEq(expectedCurrentIndex, _protocol.currentIndex(), "Protocol currentIndex is unexpected");
        assertEq(expectedUpdateTimestamp_, _protocol.latestUpdateTimestamp(), "Protocol latestUpdateTimestamp is unexpected");
    }

    function assertMTokenIndexing(
        uint256 expectedRate_, 
        uint256 expectedLatestIndex_,
        uint256 expectedCurrentIndex, 
        uint256 expectedUpdateTimestamp_
    ) internal {
        assertEq(expectedRate_, _mToken.earnerRate(), "MToken earnerRate is unexpected");
        assertEq(expectedLatestIndex_, _mToken.latestIndex(), "MToken latestIndex is unexpected");
        assertEq(expectedCurrentIndex, _mToken.currentIndex(), "MToken currentIndex is unexpected");
        assertEq(expectedUpdateTimestamp_, _mToken.latestUpdateTimestamp(), "MToken latestUpdateTimestamp is unexpected");
    }


    // SPOG Helper
    function _spogSetValue(bytes32 name_, uint256 value_) internal {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        ); 
    }

    function _spogSetValue(bytes32 name_, address value_) internal {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.get.selector, name_),
            abi.encode(value_)
        ); 
    }

    function _spogAddAccount(bytes32 list_, address account_) internal {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector, list_, account_),
            abi.encode(true)
        ); 
    }

    function _pogRemoveAccount(bytes32 list_, address account_) internal {
        vm.mockCall(
            _spogRegistrarAddress,
            abi.encodeWithSelector(ISPOGRegistrar.listContains.selector, list_, account_),
            abi.encode(false)
        ); 
    }

    // VM Helper
    function _advanceTimeBy(uint256 seconds_) internal returns (uint256) {
        _lastTimestamp = _currentTimestamp;
        _currentTimestamp += seconds_;
        vm.warp(_currentTimestamp);

        console2.log("New time is:", _currentTimestamp);

        return _currentTimestamp;
    }

}
