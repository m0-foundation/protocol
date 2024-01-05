// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { ContractHelper } from "../../lib/common/src/ContractHelper.sol";

import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";
import { MinterRateModel } from "../../src/rateModels/MinterRateModel.sol";
import { SplitEarnerRateModel } from "../../src/rateModels/SplitEarnerRateModel.sol";

import { MockTTGRegistrar } from "../utils/Mocks.sol";

import { DeployBase } from "../../script/DeployBase.s.sol";

contract ProtocolHandler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant _MINTERS_NUM = 10;
    uint256 internal constant _EARNERS_NUM = 10;
    uint256 internal constant _NON_EARNERS_NUM = 10;

    IMToken internal _mToken;
    IMinterGateway internal _minterGateway;
    MockTTGRegistrar internal _registrar;

    address[] internal _minters;
    address[] internal _earners;
    address[] internal _nonEarners;

    address internal _mockMintMinter;
    uint256 internal _currentTimestamp;

    modifier adjustTimestamp(uint256 timeJumpSeed_) {
        uint256 timeJump_ = _bound(timeJumpSeed_, 2 minutes, 10 days);
        _increaseCurrentTimestamp(timeJump_);
        vm.warp(_currentTimestamp);
        _;
    }

    constructor(IMinterGateway minterGateway_, IMToken mToken_, MockTTGRegistrar registrar_) {
        _minterGateway = minterGateway_;
        _mToken = mToken_;
        _registrar = registrar_;

        _currentTimestamp = block.timestamp;

        _initActors();
    }

    function updateBaseMinterRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 100, 40000); // [0.1%, 400%] in basis points
        console2.log("Updating minter rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_MINTER_RATE, rate_);
    }

    function updateBaseEarnerRate(uint256 timeJumpSeed_, uint256 rate_) external adjustTimestamp(timeJumpSeed_) {
        rate_ = _bound(rate_, 100, 40000); // [0.1%, 400%] in basis points
        console2.log("Updating earner rate = %s at %s", rate_, block.timestamp);
        _registrar.updateConfig(TTGRegistrarReader.BASE_EARNER_RATE, rate_);
    }

    function updateMinterGatewayIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating Minter Gateway index at %s", block.timestamp);
        _minterGateway.updateIndex();
    }

    function updateMTokenIndex(uint256 timeJumpSeed_) external adjustTimestamp(timeJumpSeed_) {
        console2.log("Updating M Token index at %s", block.timestamp);
        _mToken.updateIndex();
    }

    function mintMToEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 earnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _minters[_bound(minterIndexSeed_, 0, _MINTERS_NUM - 1)];
        address earner_ = _earners[_bound(earnerIndexSeed_, 0, _EARNERS_NUM - 1)];
        amount_ = _bound(amount_, 1e6, 1e15);

        _mintMToMHolder(minter_, earner_, amount_);
    }

    function mintMToNonEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 nonEarnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _minters[_bound(minterIndexSeed_, 0, _MINTERS_NUM - 1)];
        address nonEarner_ = _nonEarners[_bound(nonEarnerIndexSeed_, 0, _NON_EARNERS_NUM - 1)];
        amount_ = _bound(amount_, 1e6, 1e15);

        _mintMToMHolder(minter_, nonEarner_, amount_);
    }

    function burnMForMinterFromEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 earnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _minters[_bound(minterIndexSeed_, 0, _MINTERS_NUM - 1)];
        address earner_ = _earners[_bound(earnerIndexSeed_, 0, _EARNERS_NUM - 1)];
        amount_ = _bound(amount_, 1e6, _mToken.balanceOf(earner_));

        _burnMForMinterFromMHolder(minter_, earner_, amount_);
    }

    function burnMForMinterFromNonEarner(
        uint256 timeJumpSeed_,
        uint256 minterIndexSeed_,
        uint256 nonEarnerIndexSeed_,
        uint256 amount_
    ) external adjustTimestamp(timeJumpSeed_) {
        address minter_ = _minters[_bound(minterIndexSeed_, 0, _MINTERS_NUM - 1)];
        address nonEarner_ = _nonEarners[_bound(nonEarnerIndexSeed_, 0, _NON_EARNERS_NUM - 1)];
        amount_ = _bound(amount_, 1e6, _mToken.balanceOf(nonEarner_));

        _burnMForMinterFromMHolder(minter_, nonEarner_, amount_);
    }

    function deactivateMinter(uint256 timeJumpSeed_, uint256 minterIndexSeed_) external adjustTimestamp(timeJumpSeed_) {
        uint256 minterIndex_ = _bound(minterIndexSeed_, 0, _MINTERS_NUM - 1);
        address minter_ = _minters[minterIndex_];

        if (!_minterGateway.isActiveMinter(minter_)) return;

        console2.log(
            "Deactivating minter %s with active owed M %s at %s",
            minter_,
            _minterGateway.activeOwedMOf(minter_),
            block.timestamp
        );

        _registrar.removeFromList(TTGRegistrarReader.MINTERS_LIST, minter_);
        _minterGateway.deactivateMinter(minter_);
    }

    function _initActors() internal {
        _mockMintMinter = makeAddr("mockMintMinter");
        _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _mockMintMinter);
        _minterGateway.activateMinter(_mockMintMinter);

        _minters = new address[](_MINTERS_NUM);
        for (uint256 i; i < _MINTERS_NUM; ++i) {
            _minters[i] = makeAddr(string(abi.encodePacked("minter", i)));
            _registrar.addToList(TTGRegistrarReader.MINTERS_LIST, _minters[i]);
            _minterGateway.activateMinter(_minters[i]);
        }

        _earners = new address[](_EARNERS_NUM);
        for (uint256 i = 0; i < _EARNERS_NUM; ++i) {
            _earners[i] = makeAddr(string(abi.encodePacked("earner", i)));
            _registrar.addToList(TTGRegistrarReader.EARNERS_LIST, _earners[i]);

            // Start earning
            vm.prank(_earners[i]);
            _mToken.startEarning();
        }

        _nonEarners = new address[](_NON_EARNERS_NUM);
        for (uint256 i; i < _NON_EARNERS_NUM; ++i) {
            _nonEarners[i] = makeAddr(string(abi.encodePacked("nonEarner", i)));
        }
    }

    function _increaseCurrentTimestamp(uint256 timeJump_) internal {
        _currentTimestamp += timeJump_;
    }

    function _mintMToMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        if (!_minterGateway.isActiveMinter(minter_)) return;

        console2.log("Minting %s M to minter %s at %s", amount_, minter_, block.timestamp);

        uint256[] memory retrievalIds = new uint256[](0);
        address[] memory validators = new address[](0);
        uint256[] memory timestamps = new uint256[](0);
        bytes[] memory signatures = new bytes[](0);

        vm.prank(minter_);
        _minterGateway.updateCollateral(
            _minterGateway.collateralOf(minter_) + 2 * amount_,
            retrievalIds,
            bytes32(0),
            validators,
            timestamps,
            signatures
        );

        vm.prank(minter_);
        uint256 mintId_ = _minterGateway.proposeMint(amount_, mHolder_);

        vm.prank(minter_);
        _minterGateway.mintM(mintId_);
    }

    function _burnMForMinterFromMHolder(address minter_, address mHolder_, uint256 amount_) internal {
        _mintMToMHolder(_mockMintMinter, mHolder_, amount_);

        console2.log("Burning %s M for minter %s at %s", amount_, minter_, block.timestamp);

        vm.prank(mHolder_);
        _minterGateway.burnM(minter_, amount_);
    }
}

contract InvariantTests is Test {
    address internal _deployer = makeAddr("deployer");

    DeployBase internal _deploy;
    ProtocolHandler internal _handler;

    IMToken internal _mToken;
    IMinterGateway internal _minterGateway;
    MockTTGRegistrar internal _registrar;

    function setUp() public {
        _deploy = new DeployBase();
        _registrar = new MockTTGRegistrar();

        _registrar.setVault(makeAddr("vault"));

        (address minterGateway_, address minterRateModel_, address earnerRateModel_) = _deploy.deploy(
            _deployer,
            0,
            address(_registrar)
        );

        _minterGateway = IMinterGateway(minterGateway_);
        _mToken = IMToken(_minterGateway.mToken());

        _registrar.updateConfig(TTGRegistrarReader.BASE_EARNER_RATE, 400);
        _registrar.updateConfig(TTGRegistrarReader.BASE_MINTER_RATE, 400);
        _registrar.updateConfig(TTGRegistrarReader.EARNER_RATE_MODEL, earnerRateModel_);
        _registrar.updateConfig(TTGRegistrarReader.MINTER_RATE_MODEL, minterRateModel_);
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_VALIDATOR_THRESHOLD, uint256(0));
        _registrar.updateConfig(TTGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, 365 days);
        _registrar.updateConfig(TTGRegistrarReader.MINT_DELAY, uint256(0));
        _registrar.updateConfig(TTGRegistrarReader.MINT_TTL, 365 days);
        _registrar.updateConfig(TTGRegistrarReader.MINT_RATIO, 9_000);
        _registrar.updateConfig(TTGRegistrarReader.PENALTY_RATE, uint256(0));

        _minterGateway.updateIndex();

        _handler = new ProtocolHandler(_minterGateway, _mToken, _registrar);

        // Set fuzzer to only call the handler
        targetContract(address(_handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = ProtocolHandler.updateBaseMinterRate.selector;
        selectors[1] = ProtocolHandler.updateBaseEarnerRate.selector;
        selectors[2] = ProtocolHandler.mintMToEarner.selector;
        selectors[3] = ProtocolHandler.mintMToNonEarner.selector;
        selectors[4] = ProtocolHandler.deactivateMinter.selector;
        selectors[5] = ProtocolHandler.burnMForMinterFromEarner.selector;
        selectors[6] = ProtocolHandler.burnMForMinterFromNonEarner.selector;
        selectors[7] = ProtocolHandler.updateMinterGatewayIndex.selector;
        selectors[8] = ProtocolHandler.updateMTokenIndex.selector;

        targetSelector(FuzzSelector({ addr: address(_handler), selectors: selectors }));
    }

    function invariant_main() public {
        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );
        _minterGateway.updateIndex();
        assertEq(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M == total M supply"
        );
    }
}
