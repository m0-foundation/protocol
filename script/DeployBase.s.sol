// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Script, console } from "../lib/forge-std/src/Script.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";

import { ContractHelper } from "../src/libs/ContractHelper.sol";

contract DeployBase is Script {
    function deploy(
        address deployer_,
        uint256 deployerNonce_,
        address spogRegistrar_
    ) public returns (address protocol_) {
        vm.startBroadcast(deployer_);

        console.log("deployer: ", deployer_);

        // M token needs protocol address.
        // Protocol needs M token address.

        address expectedProtocol_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);
        address mToken_ = address(new MToken(expectedProtocol_, spogRegistrar_));
        protocol_ = address(new Protocol(mToken_, spogRegistrar_));

        console.log("Protocol address: ", protocol_);
        console.log("M Token address: ", mToken_);

        vm.stopBroadcast();
    }
}
