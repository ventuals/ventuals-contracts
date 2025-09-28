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
if [ -z "$OWNER_PRIVATE_KEY" ]; then
    echo "Error: OWNER_PRIVATE_KEY is not set. Please add it to your .env file or set it as an environment variable."
    exit 1
fi

if [ -z "$STAKING_VAULT_MANAGER" ]; then
    echo "Error: STAKING_VAULT_MANAGER is not set. Please add it to your .env file."
    exit 1
fi

if [ -z "$WEI_AMOUNT" ]; then
    echo "Error: WEI_AMOUNT is not set. Please add it to your .env file."
    exit 1
fi

echo "Calling transferToCoreAndDelegate function..."
echo "Contract: $STAKING_VAULT_MANAGER"
echo "Amount: $WEI_AMOUNT"
echo ""
cast send $STAKING_VAULT_MANAGER \
    "transferToCoreAndDelegate(uint256)" \
    $WEI_AMOUNT \
    --rpc-url $RPC_URL \
    --private-key $OWNER_PRIVATE_KEY

echo "Transaction sent!"
