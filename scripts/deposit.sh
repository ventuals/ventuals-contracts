#!/bin/bash

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
RPC_URL="https://rpc.hyperliquid-testnet.xyz/evm"

# Function signature: deposit()
# You can get this by running: cast sig "deposit()"

# Check if required environment variables are set
if [ -z "$ANON_WALLET_PRIVATE_KEY" ]; then
    echo "Error: ANON_WALLET_PRIVATE_KEY is not set. Please add it to your .env file or set it as an environment variable."
    exit 1
fi

if [ -z "$STAKING_VAULT_MANAGER" ]; then
    echo "Error: STAKING_VAULT_MANAGER is not set. Please add it to your .env file."
    exit 1
fi

if [ -z "$DEPOSIT_AMOUNT" ]; then
    echo "Error: DEPOSIT_AMOUNT is not set. Please add it to your .env file (in ether, e.g., 1.0)."
    exit 1
fi

echo "Calling deposit function..."
echo "Staking Vault Manager Contract: $STAKING_VAULT_MANAGER"
echo "Deposit Amount: $DEPOSIT_AMOUNT HYPE"
echo ""
cast send $STAKING_VAULT_MANAGER \
    "deposit()" \
    --value "${DEPOSIT_AMOUNT}ether" \
    --rpc-url $RPC_URL \
    --private-key $ANON_WALLET_PRIVATE_KEY

echo "Deposit transaction sent!"
