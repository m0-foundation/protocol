import * as fs from "fs";
import npmPackage from "../../package.json";

import { Contract, ContractList, Version } from "./types";

const versionSplit = npmPackage.version.split(".");
const patchSplit = versionSplit[2].split("-");

const PACKAGE_VERSION: Version = {
  major: Number(versionSplit[0]),
  minor: Number(versionSplit[1]),
  patch: Number(patchSplit[0]),
};

export const rootFolder = `${__dirname}/../..`;

const getAbi = (type: string) =>
  JSON.parse(
    fs.readFileSync(`${rootFolder}/out/${type}.sol/${type}.json`, "utf8"),
  ).abi;

const getBlob = (path: string) =>
  JSON.parse(fs.readFileSync(`${path}/run-latest.json`, "utf8"));

const formatContract = (
  chainId: number,
  name: string,
  address: `0x${string}`,
): Contract => {
  const regex = /V[1-9+]((.{0,2}[0-9+]){0,2})$/g;
  const version = name.match(regex)?.[0]?.slice(1).split(".") || [1, 0, 0];
  const type = name.split(regex)[0];

  return {
    chainId,
    address,
    version: {
      major: Number(version[0]),
      minor: Number(version[1]) || 0,
      patch: Number(version[2]) || 0,
    },
    type,
    abi: getAbi(type),
  };
};

export const generateContractList = (
  deploymentPath: string,
  networkName: string,
): ContractList => {
  const contractList: ContractList = {
    name: networkName,
    version: PACKAGE_VERSION,
    timestamp: new Date().toISOString(),
    contracts: [],
  };

  const { chain: chainId, transactions } = getBlob(deploymentPath);

  transactions.forEach(({ transactionType, contractName, contractAddress }) => {
    if (transactionType === "CREATE") {
      contractList.contracts.push(
        formatContract(chainId, contractName, contractAddress),
      );
    }
  });

  return contractList;
};

export const writeList = (
  list: ContractList,
  folderName: string,
  fileName: string,
) => {
  const dirpath = `${rootFolder}/${folderName}`;

  fs.mkdirSync(dirpath, { recursive: true });
  fs.writeFile(`${dirpath}/${fileName}.json`, JSON.stringify(list), (err) => {
    if (err) {
      console.error(err);
      return;
    }
  });
};
