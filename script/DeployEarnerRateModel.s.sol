// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Script, console2 } from "../lib/forge-std/src/Script.sol";
import { EarnerRateModel } from "../src/rateModels/EarnerRateModel.sol";

contract DeployEarnerRateModel is Script {
    // NOTE: Ensure this is the correct MinterGateway testnet/mainnet address.
    address internal constant _MINTER_GATEWAY = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E; //mainnet
    // address internal constant _MINTER_GATEWAY = 0x4eDfcfB5F9e55962EF1A2eEf0b56A8FaDbaBA289; // sepolia

    function run() external {
        address deployer_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console2.log("Deployer:", deployer_);

        vm.startBroadcast(deployer_);

        address earnerRateModel_ = address(new EarnerRateModel(_MINTER_GATEWAY));

        vm.stopBroadcast();

        console2.log("Earner Rate Model address:", earnerRateModel_);
    }
}
