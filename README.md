# M^0 Protocol

## Overview

M^0 is an EVM-compatible, immutable protocol that enables minting and burning of the ERC20 token $M. It also allows for $M distributions to yield earners and governance token ($ZERO) holders. There are three main types of actors in the protocol - Minters, Validators, and Yield Earners - all of which are permissioned via governance. Protocol variables are also managed by governance and are stored in a Registrar configuration contract.

## Development

### Installation

You may have to install the following tools to use this repository:

- [foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report
- [yarn](https://classic.yarnpkg.com/lang/en/docs/install/) to manage npm dependencies
- [slither](https://github.com/crytic/slither) to static analyze contracts

Install dependencies:

```bash
yarn
forge install
```

### Env

Copy `.env` and write down the env variables needed to run this project.

```bash
cp .env.example .env
```

### Compile

Run the following command to compile the contracts:

```bash
forge compile
```

### Coverage

Forge is used for coverage, run it with:

```bash
yarn coverage
```

You can then consult the report by opening `coverage/index.html`:

```bash
open coverage/index.html
```

### Test

To run all tests:

```bash
forge test
```

Run test that matches a test contract:

```bash
forge test --mc <test-contract-name>
```

Test a specific test case:

```bash
forge test --mt <test-case-name>
```

To run slither:

```bash
yarn slither
```

### Code quality

[Prettier](https://prettier.io) is used to format Solidity code. Use it by running:

```bash
yarn prettier
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```bash
yarn solhint
```

Or to autofix some issues:

```bash
yarn solhint-fix
```

### Documentation

Forge is used to generate the documentation. Run it with:

```bash
yarn doc
```

The command will generate the documentation in the `docs` folder and spinup a local server on port `4000` to view the documentation.

## SC Architecture

<img width="895" alt="protocol_architecture" src="https://github.com/MZero-Labs/protocol/assets/1220854/d9949243-e83b-4e1d-82ac-4d8c3f2bf5fc">
