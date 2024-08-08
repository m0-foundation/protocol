// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { DeployBase } from "./DeployBase.sol";

contract Deploy is Script, DeployBase {
    // NOTE: Ensure this is the correct Registrar testnet/mainnet address.
    address internal constant _REGISTRAR = 0x0000000000000000000000000000000000000000;

    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        console2.log("Deployer:", deployer_);

        vm.startBroadcast(deployer_);

        address mToken_ = deploy(_REGISTRAR);

        vm.stopBroadcast();

        console2.log("M Token address:", mToken_);
    }
}
