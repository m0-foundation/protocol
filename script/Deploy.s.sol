// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { DeployBase } from "./DeployBase.s.sol";

contract Deploy is DeployBase {
    // NOTE: Ensure this is the correct TTG Registrar testnet/mainnet address.
    address internal constant _TTG_REGISTRAR = 0x1EFeA064121f17379b267db17aCe135475514f8D;

    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        deploy(deployer_, _DEPLOYER_NONCE, _TTG_REGISTRAR);
    }
}
