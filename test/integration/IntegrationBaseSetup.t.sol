// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";
import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";

import { IEarnerRateModel } from "../../src/interfaces/IEarnerRateModel.sol";
import { IMinterRateModel } from "../../src/interfaces/IMinterRateModel.sol";
import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

import { DeployBase } from "../../script/DeployBase.s.sol";

import { DigestHelper } from "./../utils/DigestHelper.sol";
import { MockTTGRegistrar } from "./../utils/Mocks.sol";
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
    IMinterGateway internal _minterGateway;
    IEarnerRateModel internal _earnerRateModel;
    IMinterRateModel internal _minterRateModel;
    MockTTGRegistrar internal _registrar;

    function setUp() external {
        _deploy = new DeployBase();
        _registrar = new MockTTGRegistrar();

        _registrar.setVault(_vault);

        (address minterGateway_, address minterRateModel_, address earnerRateModel_) = _deploy.deploy(
            _deployer,
            0,
            address(_registrar)
        );

        _minterGateway = IMinterGateway(minterGateway_);
        _mToken = IMToken(_minterGateway.mToken());

        _earnerRateModel = IEarnerRateModel(earnerRateModel_);
        _minterRateModel = IMinterRateModel(minterRateModel_);

        _registrar.updateConfig(TTGRegistrarReader.BASE_EARNER_RATE, _baseEarnerRate);
        _registrar.updateConfig(TTGRegistrarReader.BASE_MINTER_RATE, _baseMinterRate);
        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, earnerRateModel_);
        _registrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, minterRateModel_);
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, 1);
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateInterval);
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, _mintDelay);
        _registrar.updateConfig(TTGRegistrarReader.MINT_TTL, _mintTtl);
        _registrar.updateConfig(TTGRegistrarReader.MINT_RATIO, _mintRatio);
        _registrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, _penaltyRate);
        _registrar.updateConfig(TTGRegistrarReader.MINTER_FREEZE_TIME, _minterFreezeTime);

        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _mHolders[0]);
        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _mHolders[1]);
        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _mHolders[2]);
        _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _mHolders[3]);

        _registrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validators[0]);
        _registrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validators[1]);
        _registrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validators[2]);
        _registrar.addToList(TTGRegistrarReader.VALIDATORS_LIST, _validators[3]);

        _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minters[0]);
        _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minters[1]);
        _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minters[2]);
        _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minters[3]);

        _minterGateway.updateIndex();
    }
}
