require('hardhat-gas-reporter');
require('@nomicfoundation/hardhat-toolbox');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.23',
    settings: {
      evmVersion: 'shanghai',
      optimizer: {
        enabled: true,
        runs: 999999
      }
    }
  },
  paths: {
    sources: './gas/contracts',
    tests: './gas/tests',
    cache: './gas/cache',
    artifacts: './gas/artifacts'
  },
  gasReporter: {
    enabled: true
  },
  mocha: {
    timeout: 180000
  }
};
