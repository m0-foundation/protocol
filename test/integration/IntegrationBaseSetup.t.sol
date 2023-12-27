// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";
import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";

import { IEarnerRateModel } from "../../src/interfaces/IEarnerRateModel.sol";
import { IMinterRateModel } from "../../src/interfaces/IMinterRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IProtocol } from "../../src/interfaces/IProtocol.sol";

import { DeployBase } from "../../script/DeployBase.s.sol";

import { DigestHelper } from "./../utils/DigestHelper.sol";
import { MockSPOGRegistrar } from "./../utils/Mocks.sol";
import { TestUtils } from "./../utils/TestUtils.sol";

/// @notice Common setup for integration tests
abstract contract IntegrationBaseSetup is TestUtils {
    address internal _deployer = makeAddr("deployer");
    address internal _vault = makeAddr("vault");

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _charlie = makeAddr("charlie");
    address internal _david = makeAddr("david");
    address internal _emma = makeAddr("emma");
    address internal _fred = makeAddr("fred");
    address internal _greg = makeAddr("greg");
    address internal _henry = makeAddr("henry");

    uint256 internal _idaKey = _makeKey("ida");
    uint256 internal _johnKey = _makeKey("john");
    uint256 internal _kenKey = _makeKey("ken");
    uint256 internal _lisaKey = _makeKey("lisa");

    address internal _ida = vm.addr(_idaKey);
    address internal _john = vm.addr(_johnKey);
    address internal _ken = vm.addr(_kenKey);
    address internal _lisa = vm.addr(_lisaKey);

    address[] internal _mHolders = [_alice, _bob, _charlie, _david];
    address[] internal _minters = [_emma, _fred, _greg, _henry];
    uint256[] internal _validatorKeys = [_idaKey, _johnKey, _kenKey, _lisaKey];
    address[] internal _validators = [_ida, _john, _ken, _lisa];

    uint256 internal _baseEarnerRate = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY
    uint256 internal _baseMinterRate = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY
    uint256 internal _updateInterval = 24 hours;
    uint256 internal _mintDelay = 3 hours;
    uint256 internal _mintTtl = 24 hours;
    uint256 internal _mintRatio = 9_000; // 90%
    uint32 internal _penaltyRate = 100; // 1%, bps
    uint32 internal _minterFreezeTime = 24 hours;

    uint256 internal _start = block.timestamp;

    DeployBase internal _deploy;
    IMToken internal _mToken;
    IProtocol internal _protocol;
    IEarnerRateModel internal _earnerRateModel;
    IMinterRateModel internal _minterRateModel;
    MockSPOGRegistrar internal _registrar;

    function setUp() external {
        _deploy = new DeployBase();
        _registrar = new MockSPOGRegistrar();

        _registrar.setVault(_vault);

        (address protocol_, address minterRateModel_, address earnerRateModel_) = _deploy.deploy(
            _deployer,
            0,
            address(_registrar)
        );

        _protocol = IProtocol(protocol_);
        _mToken = IMToken(_protocol.mToken());

        _earnerRateModel = IEarnerRateModel(earnerRateModel_);
        _minterRateModel = IMinterRateModel(minterRateModel_);

        _registrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, _baseEarnerRate);
        _registrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, _baseMinterRate);
        _registrar.updateConfig(SPOGRegistrarReader.EARNER_RATE_MODEL, earnerRateModel_);
        _registrar.updateConfig(SPOGRegistrarReader.MINTER_RATE_MODEL, minterRateModel_);
        _registrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 1);
        _registrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateInterval);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, _mintDelay);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_TTL, _mintTtl);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, _mintRatio);
        _registrar.updateConfig(SPOGRegistrarReader.PENALTY_RATE, _penaltyRate);
        _registrar.updateConfig(SPOGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);

        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _mHolders[0]);
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _mHolders[1]);
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _mHolders[2]);
        _registrar.addToList(SPOGRegistrarReader.EARNERS_LIST, _mHolders[3]);

        _registrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validators[0]);
        _registrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validators[1]);
        _registrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validators[2]);
        _registrar.addToList(SPOGRegistrarReader.VALIDATORS_LIST, _validators[3]);

        _registrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minters[0]);
        _registrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minters[1]);
        _registrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minters[2]);
        _registrar.addToList(SPOGRegistrarReader.MINTERS_LIST, _minters[3]);

        _protocol.updateIndex();
    }
}
