export type Version = {
  major: number;
  minor: number;
  patch: number;
};

export type Contract = {
  chainId: number;
  address: string;
  version: Version;
  type: string;
  abi: string;
};

export type ContractList = {
  name: string;
  version: Version;
  timestamp: string;
  contracts: Contract[];
};
