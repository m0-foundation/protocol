// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2, Test } from "../../lib/forge-std/src/Test.sol";

import { IMToken } from "../../src/interfaces/IMToken.sol";
import { IMinterGateway } from "../../src/interfaces/IMinterGateway.sol";

import { TTGRegistrarReader } from "../../src/libs/TTGRegistrarReader.sol";

import { MockTTGRegistrar } from "../utils/Mocks.sol";

import { DeployBase } from "../../script/DeployBase.s.sol";

import { ProtocolHandler } from "./handlers/ProtocolHandler.sol";

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

        bytes4[] memory selectors = new bytes4[](2);
        // selectors[0] = ProtocolHandler.updateBaseMinterRate.selector;
        // selectors[0] = ProtocolHandler.updateBaseEarnerRate.selector;
        selectors[0] = ProtocolHandler.mintMToEarner.selector;
        selectors[1] = ProtocolHandler.mintMToNonEarner.selector;
        // selectors[4] = ProtocolHandler.transferMFromNonEarnerToNonEarner.selector;
        // selectors[5] = ProtocolHandler.transferMFromEarnerToNonEarner.selector;
        // selectors[6] = ProtocolHandler.transferMFromNonEarnerToEarner.selector;
        // selectors[7] = ProtocolHandler.transferMFromEarnerToEarner.selector;
        // selectors[8] = ProtocolHandler.deactivateMinter.selector;
        // selectors[9] = ProtocolHandler.burnMForMinterFromEarner.selector;
        // selectors[10] = ProtocolHandler.burnMForMinterFromNonEarner.selector;
        // selectors[11] = ProtocolHandler.updateMinterGatewayIndex.selector;
        // selectors[12] = ProtocolHandler.updateMTokenIndex.selector;

        targetSelector(FuzzSelector({ addr: address(_handler), selectors: selectors }));

        // Prevent these contracts from being fuzzed as `msg.sender`.
        excludeSender(address(_deploy));
        excludeSender(address(_handler));
        excludeSender(address(earnerRateModel_));
        excludeSender(address(minterRateModel_));
        excludeSender(address(minterGateway_));
        excludeSender(address(_mToken));
        excludeSender(address(_registrar));
    }

    function invariant_main() public {
        // Skip test if total owed M and M token total supply are zero
        vm.assume(IMinterGateway(_minterGateway).totalOwedM() != 0);
        vm.assume(IMToken(_mToken).totalSupply() != 0);

        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M >= total M supply"
        );

        _minterGateway.updateIndex();

        // TODO: Offset of 1 wei here. Why?
        assertGe(
            IMinterGateway(_minterGateway).totalOwedM(),
            IMToken(_mToken).totalSupply(),
            "total owed M => total M supply"
        );
    }
}
