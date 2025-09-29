# Ventuals Contracts

[![Tests](https://github.com/metro-xyz/ventuals-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/metro-xyz/ventuals-contracts/actions/workflows/test.yml)
[![Lint](https://github.com/metro-xyz/ventuals-contracts/actions/workflows/lint.yml/badge.svg)](https://github.com/metro-xyz/ventuals-contracts/actions/workflows/lint.yml)

## Overview

Smart contracts for the Ventuals HYPE LST (vHYPE).

Ventuals is creating a HYPE LST (vHYPE) to raise the stake requirement for its HIP-3 deployment. Contributors deposit HYPE and receive vHYPE, a fully transferable
ERC20 issued 1:1 against their principal deposit.

vHYPE serves as a proportional claim on the underlying HYPE stake, which will grow over time as native staking yield is distributed.

## Getting Started

Install [Foundry](https://getfoundry.sh/):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Clone and set up the repository:

```bash
git clone https://github.com/metro-xyz/ventuals-contracts.git && cd ventuals-contracts
git submodule update --init --recursive
forge build
```

## Testing

```bash
# Run tests
forge test

# Run coverage report
forge coverage
```

## Security

The Ventuals smart contracts undergo independent security audits, and available audit reports are published in [docs/audits](docs/audits). We recommend
that all integrators and contributors review these reports before interacting with the contracts.

## License

The Ventuals smart contracts are licensed under Apache License 2.0.
