#!/bin/bash

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
RPC_URL="https://rpc.hyperliquid-testnet.xyz/evm"

# Function signature: addApiWallet(address,string)
# You can get this by running: cast sig "addApiWallet(address,string)"

# Check if required environment variables are set
if [ -z "$OWNER_PRIVATE_KEY" ]; then
    echo "Error: OWNER_PRIVATE_KEY is not set. Please add it to your .env file or set it as an environment variable."
    exit 1
fi

if [ -z "$STAKING_VAULT" ]; then
    echo "Error: STAKING_VAULT is not set. Please add it to your .env file."
    exit 1
fi

if [ -z "$API_WALLET_ADDRESS" ]; then
    echo "Error: API_WALLET_ADDRESS is not set. Please add it to your .env file."
    exit 1
fi

if [ -z "$API_WALLET_NAME" ]; then
    echo "Error: API_WALLET_NAME is not set. Please add it to your .env file."
    exit 1
fi

echo "Calling addApiWallet function..."
echo "Contract: $STAKING_VAULT"
echo "API Wallet Address: $API_WALLET_ADDRESS"
echo "Name: $API_WALLET_NAME"
echo ""
cast send $STAKING_VAULT \
    "addApiWallet(address,string)" \
    $API_WALLET_ADDRESS \
    "$API_WALLET_NAME" \
    --rpc-url $RPC_URL \
    --private-key $OWNER_PRIVATE_KEY

echo "Transaction sent!"
