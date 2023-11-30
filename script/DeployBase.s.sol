// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.21;

import { Script, console } from "../lib/forge-std/src/Script.sol";
import { ContractHelper } from "../lib/common/src/ContractHelper.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";

contract DeployBase is Script {
    function deploy(
        address deployer_,
        uint256 deployerNonce_,
        address spogRegistrar_
    ) public returns (address protocol_) {
        console.log("deployer: ", deployer_);

        // M token needs protocol and `spogRegistrar_` addresses.
        // Protocol needs `spogRegistrar_` and M token addresses and for `spogRegistrar_` to be deployed.

        address expectedProtocol_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);

        vm.startBroadcast(deployer_);

        address mToken_ = address(new MToken(spogRegistrar_, expectedProtocol_));
        protocol_ = address(new Protocol(spogRegistrar_, mToken_));

        vm.stopBroadcast();

        console.log("Expected Protocol_ address: ", expectedProtocol_);
        console.log("Protocol address: ", protocol_);
        console.log("M Token address: ", mToken_);
    }
}
