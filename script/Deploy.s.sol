// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { ContractHelper } from "../lib/common/src/ContractHelper.sol";

import { DeployBase } from "./DeployBase.s.sol";

contract Deploy is DeployBase {
    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        // NOTE: Ensure this is the current nonce (transaction count) of the deploying address.
        //       TTG must be deployed before this script is run.
        //       Nonce should be increased by 8 after deploying TTG.
        uint256 deployerNonce_ = vm.envUint("DEPLOYER_NONCE");

        // M token needs TTG Registrar address.
        // Zero Governor needs M token address.
        // TTG Registrar needs Zero Governor address.
        // TTG Registrar being the last deployed contract, deployerNonce_ - 1 is the nonce at which it was deployed.
        address expectedTTGRegistrar_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ - 1);

        deploy(deployer_, deployerNonce_, expectedTTGRegistrar_);
    }
}
