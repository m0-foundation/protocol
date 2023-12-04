// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, stdError, Test } from "../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../src/libs/ContinuousIndexingMath.sol";
import { SPOGRegistrarReader } from "../src/libs/SPOGRegistrarReader.sol";

import { IEarnerRateModel } from "../src/interfaces/IEarnerRateModel.sol";
import { IMinterRateModel } from "../src/interfaces/IMinterRateModel.sol";
import { IMToken } from "../src/interfaces/IMToken.sol";
import { IProtocol } from "../src/interfaces/IProtocol.sol";

import { DeployBase } from "../script/DeployBase.s.sol";

import { DigestHelper } from "./utils/DigestHelper.sol";
import { MockSPOGRegistrar } from "./utils/Mocks.sol";

// TODO: Check mints to Vault.

contract IntegrationTests is Test {
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

    uint256 internal _baseEarnerRate = ContinuousIndexingMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _baseMinterRate = ContinuousIndexingMath.BPS_BASE_SCALE / 10; // 10% APY
    uint256 internal _updateInterval = 24 hours;
    uint256 internal _mintDelay = 12 hours;
    uint256 internal _mintTtl = 24 hours;
    uint256 internal _mintRatio = 9_000; // 90%

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
        _registrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_QUORUM_VALIDATOR_THRESHOLD, 1);
        _registrar.updateConfig(SPOGRegistrarReader.UPDATE_COLLATERAL_INTERVAL, _updateInterval);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_DELAY, _mintDelay);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_TTL, _mintTtl);
        _registrar.updateConfig(SPOGRegistrarReader.MINT_RATIO, _mintRatio);

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

    function test_story1() external {
        _protocol.updateIndex();

        // Since the contracts ae deployed at the same time, these values are the same..
        uint256 latestProtocolUpdateTimestamp_ = block.timestamp;
        uint256 latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000000000000000000);
        assertEq(_protocol.currentIndex(), 1_000000000000000000);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + 2 hours); // 2 hours after deploy, minter collects signatures.

        uint256 collateral = 1_000_000e6;
        uint256 mintAmount = 500_000e6;
        uint256[] memory retrievalIds = new uint256[](0);
        uint256 signatureTimestamp = block.timestamp;

        address[] memory validators = new address[](1);
        validators[0] = _validators[0];

        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = signatureTimestamp;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _getCollateralUpdateSignature(
            _minters[0],
            collateral,
            retrievalIds,
            bytes32(0),
            signatureTimestamp,
            _validatorKeys[0]
        );

        vm.warp(block.timestamp + 1 hours); // 1 hour after collecting signatures, minter updateCollateral is mined.

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000000000000000000);
        assertEq(_protocol.currentIndex(), 1_000034247161763120);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        _protocol.activateMinter(_minters[0]);

        assertEq(_protocol.isActiveMinter(_minters[0]), true);

        vm.prank(_minters[0]);
        _protocol.updateCollateral(collateral, retrievalIds, bytes32(0), validators, timestamps, signatures);

        // Both timestamps are updated since updateIndex gets called on the protocol, and thus on the mToken.
        latestProtocolUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000034247161763120);
        assertEq(_protocol.currentIndex(), 1_000034247161763120);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + 1 hours); // 1 hour later, minter proposes a mint.

        vm.prank(_alice);
        _mToken.startEarning();

        // Only mToken is updated since mToken does not cause state changes in Protocol.
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000034247161763120);
        assertEq(_protocol.currentIndex(), 1_000045663142986194);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        uint256 mintId = _protocol.proposeMint(mintAmount, _alice);

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000034247161763120);
        assertEq(_protocol.currentIndex(), 1_000045663142986194);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.warp(block.timestamp + _mintDelay + 1 hours); // 1 hour after the mint delay, the minter mints M.

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000034247161763120);
        assertEq(_protocol.currentIndex(), 1_000194082758562665);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        vm.prank(_minters[0]);
        _protocol.mintM(mintId);

        // Both timestamps are updated since updateIndex gets called on the protocol, and thus on the mToken.
        latestProtocolUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000194082758562665);
        assertEq(_protocol.currentIndex(), 1_000194082758562665);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 999);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_000000000000000000);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 499_999_999999); // ~500k
        assertEq(_mToken.balanceOf(_alice), 500_000_000000); // 500k
        assertEq(_mToken.balanceOf(_vault), 0);

        vm.warp(block.timestamp + 356 days); // 1 year later, Alice transfers all all her M to Bob, who is not earning.

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000194082758562665);
        assertEq(_protocol.currentIndex(), 1_102663087626709063);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 999);
        assertEq(_mToken.latestIndex(), 1_000000000000000000);
        assertEq(_mToken.currentIndex(), 1_102341600326255643);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 551_224_560629); // ~500k with 10% APY compounded continuously.
        assertEq(_mToken.balanceOf(_alice), 551_170_800163); // ~500k with 10% APY compounded continuously.
        assertEq(_mToken.balanceOf(_vault), 0); // Still 0 since no call to `_protocol.updateIndex()`.

        uint256 transferAmount_ = _mToken.balanceOf(_alice);

        vm.prank(_alice);
        _mToken.transfer(_bob, transferAmount_);

        // Only mToken is updated since mToken does not cause state changes in Protocol.
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_000194082758562665);
        assertEq(_protocol.currentIndex(), 1_102663087626709063);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102341600326255643);
        assertEq(_mToken.currentIndex(), 1_102341600326255643);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 551_224_560629);
        assertEq(_mToken.balanceOf(_alice), 1); // Rounding error left over.
        assertEq(_mToken.balanceOf(_bob), 551_170_800163);
        assertEq(_mToken.balanceOf(_vault), 0); // No change since no call to `_protocol.updateIndex()`.

        vm.warp(block.timestamp + 1 hours); // 1 hour later, someone updates the indices.

        _protocol.updateIndex();

        // Both timestamps are updated since updateIndex gets called on the protocol, and thus on the mToken.
        latestProtocolUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_102675675133662193);
        assertEq(_protocol.currentIndex(), 1_102675675133662193);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102354184206304205);
        assertEq(_mToken.currentIndex(), 1_102354184206304205);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 551_230_853162);
        assertEq(_mToken.balanceOf(_bob), 551_170_800163); // Bob is not earning, so no change.
        assertEq(_mToken.balanceOf(_vault), 60_052998);

        vm.warp(block.timestamp + 1 days); // 1 day later, bob starts earning.

        vm.prank(_bob);
        _mToken.startEarning();

        // Only mToken is updated since mToken does not cause state changes in Protocol.
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_102675675133662193);
        assertEq(_protocol.currentIndex(), 1_102977819446098247);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102656240426967319);
        assertEq(_mToken.currentIndex(), 1_102656240426967319);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 551_381_896003);
        assertEq(_mToken.balanceOf(_bob), 551_170_800162);
        assertEq(_mToken.balanceOf(_vault), 60_052998); // No change since no call to `_protocol.updateIndex()`.

        vm.warp(block.timestamp + 30 days); // 30 days later, the unresponsive minter is deactivated.

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_102675675133662193);
        assertEq(_protocol.currentIndex(), 1_112080748616834297);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 1_000);
        assertEq(_mToken.latestIndex(), 1_102656240426967319);
        assertEq(_mToken.currentIndex(), 1_111756515590601303);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 555_932_477399);
        assertEq(_mToken.balanceOf(_bob), 555_719_639374);
        assertEq(_mToken.balanceOf(_vault), 60_052998); // No change since no call to `_protocol.updateIndex()`.

        _registrar.removeFromList(SPOGRegistrarReader.MINTERS_LIST, _minters[0]);

        _protocol.deactivateMinter(_minters[0]);

        // Both timestamps are updated since updateIndex gets called on the protocol, and thus on the mToken.
        latestProtocolUpdateTimestamp_ = block.timestamp;
        latestMTokenUpdateTimestamp_ = block.timestamp;

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_112080748616834297);
        assertEq(_protocol.currentIndex(), 1_112080748616834297);
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0); // Dropped to zero due to drastic change in utilization.
        assertEq(_mToken.latestIndex(), 1_111756515590601303);
        assertEq(_mToken.currentIndex(), 1_111756515590601303);
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 0);
        assertEq(_protocol.inactiveOwedMOf(_minters[0]), 555_932_477399);
        assertEq(_mToken.balanceOf(_bob), 555_719_639374);

        // Note: No change here since when `_protocol.updateIndex()` was called, the `_protocol.totalActiveM` was 0, and
        //       thus there was no `_protocol.activeOwedM` in excess of `_mToken.totalSupply` to distribute to `_vault`.
        assertEq(_mToken.balanceOf(_vault), 60_052998);

        vm.warp(block.timestamp + 30 days); // 30 more days pass without any changes to the system.

        assertEq(_protocol.minterRate(), 1_000);
        assertEq(_protocol.latestIndex(), 1_112080748616834297);
        assertEq(_protocol.currentIndex(), 1_121258804701362087); // Incased due to nonzero minter rate.
        assertEq(_protocol.latestUpdateTimestamp(), latestProtocolUpdateTimestamp_);

        assertEq(_mToken.earnerRate(), 0);
        assertEq(_mToken.latestIndex(), 1_111756515590601303);
        assertEq(_mToken.currentIndex(), 1_111756515590601303); // No change due to no earner rate in last 30 days.
        assertEq(_mToken.latestUpdateTimestamp(), latestMTokenUpdateTimestamp_);

        assertEq(_protocol.activeOwedMOf(_minters[0]), 0);
        assertEq(_protocol.inactiveOwedMOf(_minters[0]), 555_932_477399);
        assertEq(_mToken.balanceOf(_bob), 555_719_639374); // No change due to no earner rate in last 30 days.
        assertEq(_mToken.balanceOf(_vault), 60_052998); // No change since conditions did not change.
    }

    function _makeKey(string memory name) internal returns (uint256 privateKey) {
        (, privateKey) = makeAddrAndKey(name);
    }

    function _getCollateralUpdateSignature(
        address minter,
        uint256 collateral,
        uint256[] memory retrievalIds,
        bytes32 metadata,
        uint256 timestamp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        return
            _getSignature(
                DigestHelper.getUpdateCollateralDigest(
                    address(_protocol),
                    minter,
                    collateral,
                    retrievalIds,
                    metadata,
                    timestamp
                ),
                privateKey
            );
    }

    function _getSignature(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }
}
