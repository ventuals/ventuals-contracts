# Scripts

This directory contains Node.js and bash scripts for interacting with Ventuals
contracts.

We generally prefer to write Foundry scripts, but for many functions, we can't
use Foundry scripts because of HyperCore interactions. For these cases, we use
Node.js or bash scripts.

Note that it's basically equivalent to write Node.js or bash scripts. Bash scripts
use `cast send` to make the contract calls, and don't have the ABI for
typechecking.

## Getting started

From repository root:

```bash
npm install
```

## call-genesis-deposit.js

A script to deposit HYPE tokens into the GenesisVaultManager contract.

### Description

This script calls the `deposit()` function on the GenesisVaultManager contract with 0.01 HYPE.

### Prerequisites

**Environment Variables**

```bash
IS_TESTNET=true             # true for testnet, false for mainnet
GENESIS_VAULT_MANAGER=0x... # Contract address
PRIVATE_KEY=0x...           # Your wallet private key
```

**HYPE Balance**: Ensure your wallet has sufficient HYPE tokens (at least 0.01 HYPE plus gas fees)

### Usage

Run the script using npm:

```bash
npm run genesis-deposit
```

Or directly with node:

```bash
node scripts/call-genesis-deposit.js
```

### What it does

1. **Loads Configuration**: Reads environment variables from `.env` file
2. **Network Detection**: Automatically selects RPC URL based on `IS_TESTNET` flag
3. **Wallet Setup**: Connects to your wallet using the provided private key
4. **Balance Check**: Verifies you have sufficient HYPE for the deposit
5. **Transaction**: Calls `deposit()` with 0.01 HYPE
6. **Confirmation**: Waits for transaction confirmation and displays results

### Output

The script provides detailed output including:

- 🌐 Network (Testnet/Mainnet)
- 📋 Contract address being called
- 👤 Wallet address being used
- 💰 Deposit amount (0.01 HYPE)
- 💳 Current wallet balance
- ⛽ Current gas price
- 📝 Transaction hash
- ✅ Confirmation details

## call-transfer-to-core.js

A script to transfer HYPE from GenesisVaultManager's HyperEVM balance to HyperCore and delegate it to validators.

### Description

This script calls the `transferToCoreAndDelegate()` function on the GenesisVaultManager contract. This function transfers HYPE from the vault's HyperEVM balance to HyperCore and automatically delegates it to the default validator. You can either transfer all available balance or specify a specific amount.

### Prerequisites

**Environment Variables**

```bash
IS_TESTNET=true             # true for testnet, false for mainnet
GENESIS_VAULT_MANAGER=0x... # GenesisVaultManager contract address
STAKING_VAULT=0x...         # StakingVault contract address
PRIVATE_KEY=0x...           # Your wallet private key (must have OPERATOR role)
```

**Operator Role**: Your wallet must have the OPERATOR role on the GenesisVaultManager contract.

### Usage

Transfer all available balance:

```bash
npm run transfer-to-core
```

Transfer specific amount (e.g., 1.5 HYPE):

```bash
npm run transfer-to-core 1.5
```

Or directly with node:

```bash
node scripts/call-transfer-to-core.js        # Transfer all
node scripts/call-transfer-to-core.js 2.0    # Transfer 2.0 HYPE
```

### What it does

1. **Loads Configuration**: Reads environment variables from `.env` file
2. **Network Detection**: Automatically selects RPC URL based on `IS_TESTNET` flag
3. **Wallet Setup**: Connects to your operator wallet using the provided private key
4. **Amount Processing**: Uses specified amount or transfers all available balance
5. **Transaction**: Calls `transferToCoreAndDelegate()` function
6. **Core Operations**: The function internally:
   - Transfers HYPE from HyperEVM to HyperCore
   - Moves HYPE from spot to staking account
   - Delegates HYPE to the default validator
7. **Confirmation**: Waits for transaction confirmation and displays results

### Output

The script provides detailed output including:

- 🌐 Network (Testnet/Mainnet)
- 📋 Contract address being called
- 👤 Wallet address being used
- 💰 Transfer amount (specific or "All available balance")
- ⛽ Current gas price
- 📝 Transaction hash
- ✅ Confirmation details

## addApiWallet.sh

A bash script to add an API wallet to the StakingVault contract.

### Description

This script calls the `addApiWallet(address,string)` function on the StakingVault contract to register a new API wallet with a given name.

### Prerequisites

**Environment Variables**

```bash
OWNER_PRIVATE_KEY=0x...     # Private key with owner permissions
STAKING_VAULT=0x...         # StakingVault contract address
API_WALLET_ADDRESS=0x...    # Address of the API wallet to add
API_WALLET_NAME="..."       # Name for the API wallet
```

**Owner Role**: Your wallet must have owner permissions on the StakingVault contract.

### Usage

Run the script from the repository root:

```bash
./scripts/addApiWallet.sh
```

### What it does

1. **Loads Configuration**: Reads environment variables from `.env` file
2. **Validation**: Checks that all required environment variables are set
3. **Transaction**: Calls `addApiWallet()` with the specified address and name
4. **Confirmation**: Uses Foundry's `cast send` to execute the transaction

### Output

The script provides output including:

- 📋 Contract address being called
- 🔑 API wallet address being added
- 📝 Name assigned to the API wallet
- ✅ Transaction confirmation

## deposit.sh

A bash script to deposit HYPE tokens into the GenesisVaultManager contract.

### Description

This script calls the `deposit()` function on the GenesisVaultManager contract with a specified amount of HYPE tokens.

### Prerequisites

**Environment Variables**

```bash
ANON_WALLET_PRIVATE_KEY=0x... # Your wallet private key
GENESIS_VAULT_MANAGER=0x...   # GenesisVaultManager contract address
DEPOSIT_AMOUNT=1.0            # Amount to deposit in ether (e.g., 1.0 for 1 HYPE)
```

**HYPE Balance**: Ensure your wallet has sufficient HYPE tokens for the deposit plus gas fees.

### Usage

Run the script from the repository root:

```bash
./scripts/deposit.sh
```

### What it does

1. **Loads Configuration**: Reads environment variables from `.env` file
2. **Validation**: Checks that all required environment variables are set
3. **Transaction**: Calls `deposit()` with the specified HYPE amount
4. **Confirmation**: Uses Foundry's `cast send` to execute the transaction

### Output

The script provides output including:

- 📋 Genesis Vault Manager contract address
- 💰 Deposit amount in HYPE
- ✅ Transaction confirmation

## transferToCoreAndDelegate.sh

A bash script to transfer HYPE from GenesisVaultManager to HyperCore and delegate it to validators.

### Description

This script calls the `transferToCoreAndDelegate(uint256)` function on the GenesisVaultManager contract to transfer a specific amount (in wei) from the vault's HyperEVM balance to HyperCore and delegate it to validators.

### Prerequisites

**Environment Variables**

```bash
OWNER_PRIVATE_KEY=0x...     # Private key with operator permissions
GENESIS_VAULT_MANAGER=0x... # GenesisVaultManager contract address
WEI_AMOUNT=1000000000000000000  # Amount in wei (e.g., 1000000000000000000 = 1 HYPE)
```

**Operator Role**: Your wallet must have the OPERATOR role on the GenesisVaultManager contract.

### Usage

Run the script from the repository root:

```bash
./scripts/transferToCoreAndDelegate.sh
```

### What it does

1. **Loads Configuration**: Reads environment variables from `.env` file
2. **Validation**: Checks that all required environment variables are set
3. **Transaction**: Calls `transferToCoreAndDelegate()` with the specified wei amount
4. **Core Operations**: The function internally:
   - Transfers HYPE from HyperEVM to HyperCore
   - Moves HYPE from spot to staking account
   - Delegates HYPE to the default validator
5. **Confirmation**: Uses Foundry's `cast send` to execute the transaction

### Output

The script provides output including:

- 📋 Contract address being called
- 💰 Transfer amount in wei
- ✅ Transaction confirmation
