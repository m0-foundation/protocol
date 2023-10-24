// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { DeployBase } from "./DeployBase.s.sol";

contract Deploy is DeployBase {
    // NOTE: Ensure this is the current nonce (transaction count) of the deploying address.
    uint256 internal constant _DEPLOYER_NONCE = 0;

    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        deploy(deployer_, _DEPLOYER_NONCE);
    }
}
