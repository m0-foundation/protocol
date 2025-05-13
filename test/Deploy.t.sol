// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../lib/forge-std/src/Test.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";
import { IRegistrar } from "../src/interfaces/IRegistrar.sol";

import { DeployBase } from "../script/DeployBase.sol";

contract Deploy is Test, DeployBase {
    address internal constant _EXPECTED_PROXY = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;

    address internal immutable _MIGRATION_ADMIN = makeAddr("migration admin");
    address internal immutable _REGISTRAR = makeAddr("registrar");
    address internal immutable _PORTAL = makeAddr("portal");

    uint64 internal constant _DEPLOYER_PROXY_NONCE = 8;

    function test_deploy() external {
        vm.mockCall(
            _REGISTRAR,
            abi.encodeWithSelector(IRegistrar.portal.selector),
            abi.encode(_PORTAL)
        );

        // Set nonce to 1 before `_DEPLOYER_PROXY_NONCE` since implementation is deployed before proxy.
        vm.setNonce(_DEPLOYER, _DEPLOYER_PROXY_NONCE - 1);

        vm.startPrank(_DEPLOYER);
        (address implementation_, address proxy_) = deploy(_REGISTRAR, _MIGRATION_ADMIN);
        vm.stopPrank();

        // M Token Implementation assertions
        assertEq(implementation_, getExpectedMTokenImplementation(_DEPLOYER, 7));
        assertEq(IMToken(implementation_).migrationAdmin(), _MIGRATION_ADMIN);
        assertEq(IMToken(implementation_).registrar(), _REGISTRAR);
        assertEq(IMToken(implementation_).portal(), _PORTAL);

        // M Token Proxy assertions
        assertEq(proxy_, getExpectedMTokenProxy(_DEPLOYER, 7));
        assertEq(proxy_, _EXPECTED_PROXY);
        assertEq(IMToken(proxy_).migrationAdmin(), _MIGRATION_ADMIN);
        assertEq(IMToken(proxy_).registrar(), _REGISTRAR);
        assertEq(IMToken(proxy_).portal(), _PORTAL);
    }
}
