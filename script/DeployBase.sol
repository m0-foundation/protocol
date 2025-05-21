// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";

import { MToken } from "../src/MToken.sol";

contract DeployBase {
    /**
     * @dev    Deploys the M Token contract.
     * @param  registrar_      The address of the Registrar contract.
     * @param  migrationAdmin_ The address of a migration admin.
     * @return implementation_ The address of the deployed M Token implementation.
     * @return proxy_          The address of the deployed M Token proxy.
     */
    function deploy(address registrar_, address migrationAdmin_) public virtual returns (address implementation_, address proxy_) {
        implementation_ = address(new MToken(registrar_, migrationAdmin_));
        proxy_ = address(new ERC1967Proxy(implementation_, abi.encodeCall(MToken.initialize, ())));
    }

    function _getExpectedMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function getExpectedMTokenImplementation(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedMTokenImplementation(deployer_, deployerNonce_);
    }

    function _getExpectedMTokenProxy(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    function getExpectedMTokenProxy(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return _getExpectedMTokenProxy(deployer_, deployerNonce_);
    }

    function getDeployerNonceAfterMTokenDeployment(uint256 deployerNonce_) public pure virtual returns (uint256) {
        return deployerNonce_ + 2;
    }
}
