// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../../lib/forge-std/src/Test.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { ContractHelper } from "../../lib/common/src/ContractHelper.sol";
import { ContinuousIndexingMath } from "../../src/libs/ContinuousIndexingMath.sol";

import { SPOGRegistrarReader } from "../../src/libs/SPOGRegistrarReader.sol";
import { MinterRateModel } from "../../src/MinterRateModel.sol";
import { EarnerRateModel } from "../../src/EarnerRateModel.sol";

import { MockSPOGRegistrar } from "../utils/Mocks.sol";
import { ProtocolHarness } from "../utils/ProtocolHarness.sol";
import { MTokenHarness } from "../utils/MTokenHarness.sol";

import { TimestampStore } from "./stores/TimestampStore.sol";
import { Invariants } from "./Invariants.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    TimestampStore internal _timestampStore;
    ProtocolHarness internal _protocol;
    MTokenHarness internal _mToken;
    MockSPOGRegistrar internal _spogRegistrar;

    uint256 internal constant _MAX_MINTERS_NUM = 256;
    address[] internal _minters;
    uint256 internal _numMinters;

    /// @dev Simulates the passage of time. The time jump is upper bounded so that streams don't settle too quickly.
    /// See https://github.com/foundry-rs/foundry/issues/4994.
    /// @param timeJumpSeed_ A fuzzed value needed for generating random time warps.
    modifier adjustTimestamp(uint256 timeJumpSeed_) {
        uint256 timeJump_ = bound(timeJumpSeed_, 2 minutes, 10 days);
        console2.log("Time jump = ", timeJump_);
        _timestampStore.increaseCurrentTimestamp(timeJump_);
        vm.warp(_timestampStore.currentTimestamp());
        _;
    }

    /// @dev Checks user assumptions.
    modifier checkUser(address user_) {
        // The protocol doesn't minter or earner to be zero address.
        if (user_ == address(0)) return;

        _;
    }

    constructor(
        ProtocolHarness protocol_,
        MTokenHarness mToken_,
        MockSPOGRegistrar spogRegistrar_,
        TimestampStore timestampStore_
    ) {
        _protocol = protocol_;
        _mToken = mToken_;
        _spogRegistrar = spogRegistrar_;
        _timestampStore = timestampStore_;

        _minters = new address[](_MAX_MINTERS_NUM);
    }

    function updateMinterRate(uint256 timeJumpSeed, uint32 rate_) external adjustTimestamp(timeJumpSeed) {
        rate_ = uint32(bound(rate_, 100, 40000)); // [0.1%, 400%] in basis points
        console2.log("Updating minter rate = %s at %s", rate_, block.timestamp);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, rate_);
    }

    function updateEarnerRate(uint256 timeJumpSeed, uint32 rate_) external adjustTimestamp(timeJumpSeed) {
        rate_ = uint32(bound(rate_, 100, 40000)); // [0.1%, 400%] in basis points
        console2.log("Updating earner rate = %s at %s", rate_, block.timestamp);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, rate_);
    }

    function setMinterPrincipal(
        uint256 timeJumpSeed,
        address minter_,
        uint128 principal_
    ) external adjustTimestamp(timeJumpSeed) checkUser(minter_) {
        if (_numMinters == _MAX_MINTERS_NUM) return;

        principal_ = uint128(bound(principal_, 1, 1e15));

        console2.log("Setting principal = %s for minter %s at %s", principal_, minter_, block.timestamp);

        _spogRegistrar.addToList(SPOGRegistrarReader.MINTERS_LIST, minter_);
        _protocol.activateMinter(minter_);

        _protocol.setPrincipalOfActiveOwedMOf(minter_, principal_);

        _minters[_numMinters++] = minter_;

        _protocol.updateIndex();
    }

    function setEarnerPrincipal(
        uint256 timeJumpSeed,
        address earner_,
        uint128 principal_
    ) external adjustTimestamp(timeJumpSeed) checkUser(earner_) {
        uint256 maxPrincipal_ = ContinuousIndexingMath.divideDown(
            (_protocol.totalOwedM() - uint128(_mToken.totalSupply())),
            _mToken.latestIndex()
        );
        principal_ = uint128(bound(principal_, 0, maxPrincipal_));

        console2.log("Setting principal = %s for earner %s at %s", principal_, earner_, block.timestamp);

        _spogRegistrar.addToList(SPOGRegistrarReader.EARNERS_LIST, earner_);

        _mToken.setIsEarning(earner_, true);
        _mToken.setInternalBalanceOf(earner_, principal_);
        uint256 previousTotalPrincipal_ = _mToken.totalPrincipalOfEarningSupply();
        _mToken.setTotalPrincipalOfEarningSupply(previousTotalPrincipal_ + principal_);

        _mToken.updateIndex();
    }

    function setEarnerBalance(
        uint256 timeJumpSeed,
        address earner_,
        uint128 balance_
    ) external adjustTimestamp(timeJumpSeed) checkUser(earner_) {
        balance_ = uint128(bound(balance_, 0, _protocol.totalOwedM() - uint128(_mToken.totalSupply())));

        console2.log("Setting balance = %s for earner %s at %s", balance_, earner_, block.timestamp);

        _mToken.setInternalBalanceOf(earner_, balance_);
        uint256 previousTotalNonEarningSupply_ = _mToken.totalNonEarningSupply();
        _mToken.setTotalNonEarningSupply(previousTotalNonEarningSupply_ + balance_);

        _mToken.updateIndex();
    }

    function deactivateMinter(uint256 timeJumpSeed, uint256 minterIndexSeed_) external adjustTimestamp(timeJumpSeed) {
        if (_numMinters == 0) return;

        uint256 minterIndex_ = bound(minterIndexSeed_, 0, _numMinters - 1);
        address minter_ = _minters[minterIndex_];

        if (!_protocol.isActiveMinter(minter_)) return;

        console2.log(
            "Deactivating minter %s with active owed M %s at %s",
            minter_,
            _protocol.activeOwedMOf(minter_),
            block.timestamp
        );

        _spogRegistrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, minter_);
        _protocol.deactivateMinter(minter_);
    }

    function burnM(
        uint256 timeJumpSeed,
        uint256 minterIndexSeed_,
        uint256 maxAmount_
    ) external adjustTimestamp(timeJumpSeed) {
        maxAmount_ = uint128(bound(maxAmount_, 1, 1e15));
        address minter_ = _minters[bound(minterIndexSeed_, 0, _numMinters - 1)];

        // _printMinters();
        console2.log("Burning %s M from minter %s at %s", maxAmount_, minter_, block.timestamp);

        // TODO min M to user
        _protocol.burnM(minter_, maxAmount_);
    }

    function _printMinters() internal {
        for (uint256 i = 0; i < _numMinters; i++) {
            console2.log("minter %s = %s", i, _minters[i]);
        }
    }
}

contract Protocol_Handler_Based_Invariant_Tests is Test {
    Handler internal _handler;
    TimestampStore internal _timestampStore;

    MockSPOGRegistrar internal _spogRegistrar;
    MTokenHarness internal _mToken;
    ProtocolHarness internal _protocol;

    function setUp() public {
        _spogRegistrar = new MockSPOGRegistrar();
        _spogRegistrar.setVault(makeAddr("vault"));

        address deployer_ = makeAddr("deployer");
        address expectedProtocol_ = ContractHelper.getContractFrom(deployer_, 1);

        vm.startBroadcast(deployer_);

        _mToken = new MTokenHarness(address(_spogRegistrar), expectedProtocol_);
        _protocol = new ProtocolHarness(address(_spogRegistrar), address(_mToken));

        vm.stopBroadcast();

        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.MINTER_RATE_MODEL,
            address(new MinterRateModel(address(_spogRegistrar)))
        );
        _spogRegistrar.updateConfig(
            SPOGRegistrarReader.EARNER_RATE_MODEL,
            address(new EarnerRateModel(address(_protocol)))
        );

        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_MINTER_RATE, 4000);
        _spogRegistrar.updateConfig(SPOGRegistrarReader.BASE_EARNER_RATE, 4000);

        _timestampStore = new TimestampStore();
        _handler = new Handler(_protocol, _mToken, _spogRegistrar, _timestampStore);

        _protocol.updateIndex();

        // Set fuzzer to only call the handler
        targetContract(address(_handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.updateMinterRate.selector;
        selectors[1] = Handler.updateEarnerRate.selector;
        selectors[2] = Handler.setMinterPrincipal.selector;
        selectors[3] = Handler.setEarnerPrincipal.selector;
        selectors[4] = Handler.setEarnerBalance.selector;
        selectors[5] = Handler.deactivateMinter.selector;
        // selectors[6] = Handler.burnM.selector;

        targetSelector(FuzzSelector({ addr: address(_handler), selectors: selectors }));
    }

    function invariant_main() public {
        assertTrue(Invariants.checkInvariant1(address(_protocol), address(_mToken)), "total owed M >= total supply");
        _protocol.updateIndex();
        assertTrue(Invariants.checkInvariant2(address(_protocol), address(_mToken)), "total owed M = total supply");
    }
}
