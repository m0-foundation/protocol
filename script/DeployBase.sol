// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContractHelper } from "../lib/common/src/ContractHelper.sol";

import { MinterGateway } from "../src/MinterGateway.sol";
import { MToken } from "../src/MToken.sol";
import { StableEarnerRateModel } from "../src/rateModels/StableEarnerRateModel.sol";
import { MinterRateModel } from "../src/rateModels/MinterRateModel.sol";

contract DeployBase {
    /**
     * @dev    Deploys TTG.
     * @param  deployer_        The address of the account deploying the contracts.
     * @param  deployerNonce_   The current nonce of the deployer.
     * @param  ttgRegistrar_    The address of the TTG Registrar.
     * @return minterGateway_   The address of the deployed Minter Gateway.
     * @return minterRateModel_ The address of the deployed Minter Rate Model.
     * @return earnerRateModel_ The address of the deployed Earner Rate Model.
     */
    function deploy(
        address deployer_,
        uint256 deployerNonce_,
        address ttgRegistrar_
    ) public virtual returns (address minterGateway_, address minterRateModel_, address earnerRateModel_) {
        // M token needs `minterGateway_` and `ttgRegistrar_` addresses.
        // MinterGateway needs `ttgRegistrar_` and M token addresses and for `ttgRegistrar_` to be deployed.
        // EarnerRateModel needs `minterGateway_` address and for `minterGateway_` to be deployed.
        // MinterRateModel needs `ttgRegistrar_` address.

        address mToken_ = address(new MToken(ttgRegistrar_, getExpectedMinterGateway(deployer_, deployerNonce_)));

        minterGateway_ = address(new MinterGateway(ttgRegistrar_, mToken_));
        minterRateModel_ = address(new MinterRateModel(ttgRegistrar_));
        earnerRateModel_ = address(new StableEarnerRateModel(minterGateway_));
    }

    function getExpectedMToken(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_);
    }

    function getExpectedMinterGateway(address deployer_, uint256 deployerNonce_) public pure virtual returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
    }

    function getExpectedMinterRateModel(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 2);
    }

    function getExpectedEarnerRateModel(
        address deployer_,
        uint256 deployerNonce_
    ) public pure virtual returns (address) {
        return ContractHelper.getContractFrom(deployer_, deployerNonce_ + 3);
    }

    function getDeployerNonceAfterProtocolDeployment(uint256 deployerNonce_) public pure virtual returns (uint256) {
        return deployerNonce_ + 4;
    }
}
