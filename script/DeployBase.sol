// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { ContractHelper } from "../lib/common/src/libs/ContractHelper.sol";

import { MToken } from "../src/MToken.sol";

contract DeployBase {
    /**
     * @dev    Deploys the M Token contract.
     * @param  registrar_ The address of the Registrar contract.
     * @return mToken_    The address of the deployed M Token contract.
     */
    function deploy(address registrar_) public virtual returns (address mToken_) {
        // M token needs `registrar_` addresses.
        return address(new MToken(registrar_));
    }

    function _getExpectedMToken(address deployer_, uint256 deployerNonce_) internal pure returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function getExpectedMToken(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return _getExpectedMToken(deployer_, deployerNonce_);
    }

    function getDeployerNonceAfterMTokenDeployment(uint256 deployerNonce_) public pure virtual returns (uint256) {
        return deployerNonce_ + 1;
    }
}
