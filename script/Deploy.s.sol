// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { Script, console } from "../lib/forge-std/src/Script.sol";

import { Protocol } from "../src/Protocol.sol";
import { MToken } from "../src/MToken.sol";

import { ContractHelper } from "../src/libs/ContractHelper.sol";

contract Deploy is Script {
    uint256 internal constant _DEPLOYER_STARTING_NONCE = 0;

    address internal _deployer;
    address internal _protocol;
    address internal _mToken;

    function setUp() public {
        string memory mnemonic = vm.envString("MNEMONIC");

        (_deployer, ) = deriveRememberKey(mnemonic, 0);

        console.log("deployer: %s", _deployer);
    }

    function run() public {
        vm.startBroadcast(_deployer);

        address expectedProtocol_ = ContractHelper.getContractFrom(_deployer, _DEPLOYER_STARTING_NONCE + 1);
        _mToken = address(new MToken(expectedProtocol_));
        _protocol = address(new Protocol(_mToken));

        console.log("Protocol address: ", _protocol);
        console.log("M Token address: ", _mToken);

        vm.stopBroadcast();
    }
}
