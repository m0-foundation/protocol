// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Script, console } from "../lib/forge-std/src/Script.sol";
import { ContractHelper } from "../lib/common/src/ContractHelper.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";
import { EarnerRateModel } from "../src/EarnerRateModel.sol";
import { MinterRateModel } from "../src/MinterRateModel.sol";

contract DeployBase is Script {
    function deploy(
        address deployer_,
        uint256 deployerNonce_,
        address ttgRegistrar_
    ) public returns (address protocol_, address minterRateModel_, address earnerRateModel_) {
        console.log("deployer: ", deployer_);

        // M token needs protocol and `ttgRegistrar_` addresses.
        // Protocol needs `ttgRegistrar_` and M token addresses and for `ttgRegistrar_` to be deployed.
        // EarnerRateModel needs protocol address and for protocol to be deployed.
        // MinterRateModel needs `ttgRegistrar_` address.

        address expectedProtocol_ = ContractHelper.getContractFrom(deployer_, deployerNonce_ + 1);

        vm.startBroadcast(deployer_);

        address mToken_ = address(new MToken(ttgRegistrar_, expectedProtocol_));

        protocol_ = address(new Protocol(ttgRegistrar_, mToken_));
        minterRateModel_ = address(new MinterRateModel(ttgRegistrar_));
        earnerRateModel_ = address(new EarnerRateModel(protocol_));

        vm.stopBroadcast();

        console.log("Expected Protocol_ address: ", expectedProtocol_);
        console.log("Protocol address: ", protocol_);
        console.log("M Token address: ", mToken_);
        console.log("Earner Rate Model address: ", earnerRateModel_);
        console.log("Minter Rate Model address: ", minterRateModel_);
    }
}
