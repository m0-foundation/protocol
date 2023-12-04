// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { DeployBase } from "./DeployBase.s.sol";

contract Deploy is DeployBase {
    // NOTE: Ensure this is the correct SPOG Registrar testnet/mainnet address.
    address internal constant _SPOG_REGISTRAR = 0x1EFeA064121f17379b267db17aCe135475514f8D;

    // NOTE: Ensure this is the current nonce (transaction count) of the deploying address.
    uint256 internal constant _DEPLOYER_NONCE = 0;

    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        deploy(deployer_, _DEPLOYER_NONCE, _SPOG_REGISTRAR);
    }
}
