# Vault Smart Contracts

## Getting Started

```sh
bun install
```

If this is your first time with Foundry, check out the
[installation](https://github.com/foundry-rs/foundry#installation) instructions.

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
forge clean
```

### Compile

Compile the contracts:

```sh
forge build
```

### Coverage

Get a test coverage report:

```sh
forge coverage
```

### Deploy

Deploy to Anvil:

```sh
forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
forge fmt
```

### Gas Usage

Get a gas report:

```sh
forge test --gas-report
```

### Lint

Lint the contracts:

```sh
bun run lint
```

### Test

Run the tests:

```sh
forge test
```

### Test Coverage

Generate test coverage and output result to the terminal:

```sh
bun run test:coverage
```

### Test Coverage Report

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
bun run test:coverage:report
```

> [!NOTE]
>
> This command requires you to have [`lcov`](https://github.com/linux-test-project/lcov) installed on your machine. On
> macOS, you can install it with Homebrew: `brew install lcov`.

Period | Who | Stake | Reward Calculation | Result (wei) 0s - 10s | Alice | 100e18 | 10s _ 31709791983764586 |
317097919837645860 10s - 20s | Alice | 100e18 | (10s _ 31709791983764586 _ 100e18 / 400e18) | 79274479959411465 10s -
20s | Bob | 300e18 | (10s _ 31709791983764586 \* 300e18 / 400e18) | 237823439878234395 | | | | Total | Alice | |
317097919837645860 + 79274479959411465 | 396372399797057325 Total | Bob | | 237823439878234395 | 237823439878234395
Distributed | All | | 396372399797057325 + 237823439878234395 | 634195839675291720
