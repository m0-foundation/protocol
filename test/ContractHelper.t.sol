// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Test } from "../lib/forge-std/src/Test.sol";

import { ContractHelper } from "../src/libs/ContractHelper.sol";

contract Void {}

contract VoidDeployer {
    function deploy() external returns (address deployed_) {
        deployed_ = address(new Void());
    }
}

contract ContractHelperTests is Test {
    VoidDeployer internal _voidDeployer;

    function setUp() external {
        _voidDeployer = new VoidDeployer();
    }

    function test_full() external {
        vm.setNonce(address(_voidDeployer), 0x00 + 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0x00 + 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0x7f - 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0x7f - 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0x7f);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0x7f), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0x7f + 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0x7f + 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xff - 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xff - 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xff);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xff), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xff + 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xff + 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffff - 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffff - 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffff);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffff), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffff + 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffff + 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffffff - 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffffff - 1), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffffff);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffffff), _voidDeployer.deploy());

        vm.setNonce(address(_voidDeployer), 0xffffff + 1);
        assertEq(ContractHelper.getContractFrom(address(_voidDeployer), 0xffffff + 1), _voidDeployer.deploy());
    }
}
