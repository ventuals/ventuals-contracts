# Ventuals Contracts

[![Tests](https://github.com/ventuals/ventuals-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/ventuals/ventuals-contracts/actions/workflows/test.yml)
[![Lint](https://github.com/ventuals/ventuals-contracts/actions/workflows/lint.yml/badge.svg)](https://github.com/ventuals/ventuals-contracts/actions/workflows/lint.yml)

## Overview

Smart contracts for the Ventuals HYPE LST (vHYPE).

Ventuals is raising HYPE through a custom liquid staking token (LST) for its
HIP-3 deployment. Contributors receive vHYPE, which is a fully transferable
ERC20 that represents a claim on the underlying HYPE principal.

- Minimum stake: 500k HYPE must remain staked with validators, which is the
  current requirement for HIP-3 deployers.
- Liquidity: Additional deposits provide a liquidity buffer for withdrawals.
- Native yield: All native staking yield accrues proportionally to vHYPE holders.

## Getting Started

Install [Foundry](https://getfoundry.sh/):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Clone and set up the repository:

```bash
git clone https://github.com/ventuals/ventuals-contracts.git && cd ventuals-contracts
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
