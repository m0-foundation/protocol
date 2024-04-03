// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";

import { IMinterGateway } from "../src/interfaces/IMinterGateway.sol";

import { DeployBase } from "./DeployBase.sol";

contract Deploy is Script, DeployBase {
    // NOTE: Ensure this is the correct TTG Registrar testnet/mainnet address.
    address internal constant _TTG_REGISTRAR = 0x1EFeA064121f17379b267db17aCe135475514f8D;

    function run() external {
        (address deployer_, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);

        console2.log("Deployer:", deployer_);

        vm.startBroadcast(deployer_);

        (address minterGateway_, address minterRateModel_, address earnerRateModel_) = deploy(
            deployer_,
            vm.getNonce(deployer_),
            _TTG_REGISTRAR
        );

        vm.stopBroadcast();

        console2.log("Minter Gateway address:", minterGateway_);
        console2.log("M Token address:", IMinterGateway(minterGateway_).mToken());
        console2.log("Earner Rate Model address:", earnerRateModel_);
        console2.log("Minter Rate Model address:", minterRateModel_);
    }
}
