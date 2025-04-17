# Staking Contract

This repository contains a staking vault system designed for continuous, fair, and proportional distribution of ERC-20
reward tokens to users who lock/stake another ERC-20 token over a fixed duration. The system tracks both global and
per-user state to ensure accurate reward calculation.

## Table of Contents

- [Background](#background)
- [How It Works](#how-it-works)
- [Key Features](#key-features)
- [Example Scenarios](#example-scenarios)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Development](#development)
- [Testing](#testing)
- [License](#license)

## Background

> A protocol wants to distribute 1 million reward tokens (`tokenR`) over 1 year to users who stake `tokenT`. Rewards are
> distributed **continuously** and **proportionally** to the amount of `tokenT` staked. Users should be able to claim
> rewards at any time without withdrawing their stake.

The smart contract implements this requirement using an accumulator-based approach that ensures precision and
efficiency, even as new users join or exit the staking pool.

## How It Works

- Users stake `tokenT` into the contract
- Rewards (`tokenR`) are distributed continuously over time to all active stakers
- The distribution is **proportional to each user's share** of the total stake
- Users can **claim rewards** at any time without withdrawing their stake

Internally, the contract tracks a `rewardAccumulator` value that captures the amount of `tokenR` per `tokenT` staked.
Each user has a `rewardCheckpoint` that notes the last value they interacted with.

## Key Features

- Continuous reward emission
- Supports multiple users entering and exiting at arbitrary times
- Accumulates rewards precisely using `FullMath.mulDiv` (from Uniswap V4)
- Low gas overhead through packed structs
- Withdraw without auto-claiming
- Safe and secure with `ReentrancyGuard`

## Example Scenarios

### Simple Two-User Scenario

```
Time (s):   0      10     20
User A:     stake         claim
User B:            stake  claim

Reward Rate: 1 tokenR/sec

0–10s: Only A staked 100 tokenT → 10 tokenR → All goes to A
10–20s: A has 100, B has 300 → 10 tokenR
    A gets 2.5 (100/400), B gets 7.5 (300/400)

Result:
- A gets 10 + 2.5 = 12.5 tokenR
- B gets 7.5 tokenR
```

### Three Users with Gaps

```
Time (s):   0      30     40     70     100
Alice:      stake  exit
Bob:                      stake        claim
Eve:                             stake  claim

Reward Rate: 31.709791983764586e15 tokenR/sec

Alice earns 30s of full rewards
Bob earns 30s alone + 30s shared (40%)
Eve earns 30s shared (60%)
```

## Getting Started

```sh
bun install
```

If you're new to [Foundry](https://github.com/foundry-rs/foundry):

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Project Structure

- `src/`
  - `Staking.sol` — Main staking logic
  - `interfaces/IStaking.sol` — Interface with documentation
  - `types/DataTypes.sol` — Packed `UserInfo` struct
  - `libraries/Errors.sol` — Custom errors
- `test/` — Foundry tests (fuzz, invariant)
- `script/` — deployment scripts

## Development

### Compile

```sh
forge build
```

### Format

```sh
forge fmt
```

### Clean

```sh
forge clean
```

### Lint

```sh
bun run lint
```

### Deploy (Anvil local fork)

```sh
forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

> Requires a `MNEMONIC` environment variable for signer.

## Testing

### Unit + Fuzz Tests

```sh
forge test
```

### Gas Report

```sh
forge test --gas-report
```

### Coverage (basic)

```sh
forge coverage
```

### Coverage Report (HTML)

```sh
bun run test:coverage:report
```

> Requires [lcov](https://github.com/linux-test-project/lcov). On macOS:
>
> ```sh
> brew install lcov
> ```
