import {
  generateContractList,
  rootFolder,
  writeList,
} from "../helpers/generateContractList";

writeList(
  generateContractList(
    `${rootFolder}/broadcast/Deploy.s.sol/11155111`,
    "Protocol - Sepolia Testnet",
  ),
  "deployments/sepolia",
  "contracts",
);
