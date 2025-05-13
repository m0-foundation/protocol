// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { Test } from "../lib/forge-std/src/Test.sol";
import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IMToken } from "../src/interfaces/IMToken.sol";
import { IRegistrar } from "../src/interfaces/IRegistrar.sol";

import { MToken } from "../src/MToken.sol";

contract MTokenV2 {
    function foo() external pure returns (uint256) {
        return 1;
    }
}

contract MTokenMigratorV1 {
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    address public immutable implementationV2;

    constructor(address implementationV2_) {
        implementationV2 = implementationV2_;
    }

    fallback() external virtual {
        bytes32 slot_ = _IMPLEMENTATION_SLOT;
        address implementationV2_ = implementationV2;

        assembly {
            sstore(slot_, implementationV2_)
        }
    }
}

contract MigrationTests is Test {
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "m_migrator_v1";

    address internal _migrationAdmin = makeAddr("migrationAdmin");
    address internal _registrar = makeAddr("registrar");
    address internal _portal = makeAddr("portal");

    MToken internal _implementation;
    MToken internal _mToken;

    function setUp() external {
        vm.mockCall(
            _registrar,
            abi.encodeWithSelector(IRegistrar.portal.selector),
            abi.encode(_portal)
        );

        _implementation = new MToken(_registrar, _migrationAdmin);
        _mToken = MToken(address(new ERC1967Proxy(address(_implementation), abi.encodeCall(IMToken.initialize, ()))));
    }

    function test_migration() external {
        MTokenV2 implementationV2_ = new MTokenV2();
        address migrator_ = address(new MTokenMigratorV1(address(implementationV2_)));

        vm.expectRevert();
        MTokenV2(address(_mToken)).foo();

        vm.prank(_migrationAdmin);
        _mToken.migrate(migrator_);

        assertEq(MTokenV2(address(_mToken)).foo(), 1);
    }
}
