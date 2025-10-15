#!/bin/bash
# grind-salts.sh - Grind CREATE2 salts for all contracts
# Usage: ./grind-salts.sh

set -e

# Configuration
# TODO: Update these values for the current environment
OWNER=
IS_TESTNET=
IS_TEST_VAULT=

# Vault config for mainnet production
# TODO: Check that these match the values in DeployContracts.s.sol
MIN_STAKE_BALANCE=500000000000000000000000  # 500k HYPE
MIN_DEPOSIT=1000000000000000000  # 1 HYPE
MIN_WITHDRAW=500000000000000000  # 0.5 HYPE
MAX_WITHDRAW=10000000000000000000000  # 10k HYPE

# Mainnet configuration
VALIDATOR=0x5aC99df645F3414876C816Caa18b2d234024b487
VALIDATOR_1=0x5aC99df645F3414876C816Caa18b2d234024b487
VALIDATOR_2=0xA82FE73bBD768bC15D1eF2F6142a21fF8bD762AD
VALIDATOR_3=0x80f0CD23DA5BF3a0101110cfD0F89C8a69a1384d
VALIDATOR_4=0xdF35aee8ef5658686142ACd1E5AB5DBcDF8c51e8
VALIDATOR_5=0x66Be52ec79F829Cc88E5778A255E2cb9492798fd
HYPE_TOKEN_ID=150

echo "======================================"
echo "CREATE2 Salt Grinding Script"
echo "======================================"
echo "Owner: $OWNER"
echo "Validator: $VALIDATOR"
echo ""

# Compile contracts first
echo "=== Compiling contracts ==="
forge build
echo ""

# ============================================
# STEP 1: Grind Implementation Salts
# ============================================
echo "=== STEP 1: Grinding Implementation Salts ==="
echo ""

# 1. RoleRegistry Implementation
echo "1/4 Grinding RoleRegistry Implementation..."
ROLE_REGISTRY_IMPL_BYTECODE=$(forge inspect RoleRegistry bytecode)
ROLE_REGISTRY_IMPL_RESULT=$(cast create2 --starts-with 0000000 --init-code $ROLE_REGISTRY_IMPL_BYTECODE)
ROLE_REGISTRY_IMPL=$(echo "$ROLE_REGISTRY_IMPL_RESULT" | grep "Address:" | awk '{print $2}')
ROLE_REGISTRY_IMPL_SALT=$(echo "$ROLE_REGISTRY_IMPL_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $ROLE_REGISTRY_IMPL"
echo "   Salt: $ROLE_REGISTRY_IMPL_SALT"
echo ""

# 2. VHYPE Implementation
echo "2/4 Grinding VHYPE Implementation..."
VHYPE_IMPL_BYTECODE=$(forge inspect VHYPE bytecode)
VHYPE_IMPL_RESULT=$(cast create2 --starts-with 0000000 --init-code $VHYPE_IMPL_BYTECODE)
VHYPE_IMPL=$(echo "$VHYPE_IMPL_RESULT" | grep "Address:" | awk '{print $2}')
VHYPE_IMPL_SALT=$(echo "$VHYPE_IMPL_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $VHYPE_IMPL"
echo "   Salt: $VHYPE_IMPL_SALT"
echo ""

# 3. StakingVault Implementation (with constructor arg!)
echo "3/4 Grinding StakingVault Implementation..."
STAKING_VAULT_IMPL_CREATION_CODE=$(forge inspect StakingVault bytecode)
STAKING_VAULT_IMPL_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint64)" $HYPE_TOKEN_ID)
STAKING_VAULT_IMPL_INIT_CODE=$(cast concat-hex $STAKING_VAULT_IMPL_CREATION_CODE $STAKING_VAULT_IMPL_CONSTRUCTOR_ARGS)
STAKING_VAULT_IMPL_RESULT=$(cast create2 --starts-with 0000000 --init-code $STAKING_VAULT_IMPL_INIT_CODE)
STAKING_VAULT_IMPL=$(echo "$STAKING_VAULT_IMPL_RESULT" | grep "Address:" | awk '{print $2}')
STAKING_VAULT_IMPL_SALT=$(echo "$STAKING_VAULT_IMPL_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $STAKING_VAULT_IMPL"
echo "   Salt: $STAKING_VAULT_IMPL_SALT"
echo ""

# 4. StakingVaultManager Implementation
echo "4/4 Grinding StakingVaultManager Implementation..."
STAKING_VAULT_MANAGER_IMPL_BYTECODE=$(forge inspect StakingVaultManager bytecode)
STAKING_VAULT_MANAGER_IMPL_RESULT=$(cast create2 --starts-with 0000000 --init-code $STAKING_VAULT_MANAGER_IMPL_BYTECODE)
STAKING_VAULT_MANAGER_IMPL=$(echo "$STAKING_VAULT_MANAGER_IMPL_RESULT" | grep "Address:" | awk '{print $2}')
STAKING_VAULT_MANAGER_IMPL_SALT=$(echo "$STAKING_VAULT_MANAGER_IMPL_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $STAKING_VAULT_MANAGER_IMPL"
echo "   Salt: $STAKING_VAULT_MANAGER_IMPL_SALT"
echo ""

# ============================================
# STEP 2: Grind Proxy Salts
# ============================================
echo "=== STEP 2: Grinding Proxy Salts ==="
echo ""

# Get ERC1967Proxy bytecode (reused for all proxies)
PROXY_BYTECODE=$(forge inspect ERC1967Proxy bytecode)

# 1. RoleRegistry Proxy
echo "1/4 Grinding RoleRegistry Proxy..."
ROLE_REGISTRY_INIT_DATA=$(cast calldata "initialize(address)" $OWNER)
ROLE_REGISTRY_PROXY_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" $ROLE_REGISTRY_IMPL $ROLE_REGISTRY_INIT_DATA)
ROLE_REGISTRY_PROXY_INIT_CODE=$(cast concat-hex $PROXY_BYTECODE $ROLE_REGISTRY_PROXY_CONSTRUCTOR_ARGS)
ROLE_REGISTRY_PROXY_RESULT=$(cast create2 --starts-with 8888888 --init-code $ROLE_REGISTRY_PROXY_INIT_CODE)
ROLE_REGISTRY_PROXY=$(echo "$ROLE_REGISTRY_PROXY_RESULT" | grep "Address:" | awk '{print $2}')
ROLE_REGISTRY_PROXY_SALT=$(echo "$ROLE_REGISTRY_PROXY_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $ROLE_REGISTRY_PROXY"
echo "   Salt: $ROLE_REGISTRY_PROXY_SALT"
echo ""

# 2. VHYPE Proxy
echo "2/4 Grinding VHYPE Proxy..."
VHYPE_INIT_DATA=$(cast calldata "initialize(address)" $ROLE_REGISTRY_PROXY)
VHYPE_PROXY_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" $VHYPE_IMPL $VHYPE_INIT_DATA)
VHYPE_PROXY_INIT_CODE=$(cast concat-hex $PROXY_BYTECODE $VHYPE_PROXY_CONSTRUCTOR_ARGS)
VHYPE_PROXY_RESULT=$(cast create2 --starts-with 8888888 --init-code $VHYPE_PROXY_INIT_CODE)
VHYPE_PROXY=$(echo "$VHYPE_PROXY_RESULT" | grep "Address:" | awk '{print $2}')
VHYPE_PROXY_SALT=$(echo "$VHYPE_PROXY_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $VHYPE_PROXY"
echo "   Salt: $VHYPE_PROXY_SALT"
echo ""

# 3. StakingVault Proxy
echo "3/4 Grinding StakingVault Proxy..."
# Encode the validators array - need to pass addresses individually
STAKING_VAULT_INIT_DATA=$(cast calldata "initialize(address,address[])" $ROLE_REGISTRY_PROXY "[$VALIDATOR_1,$VALIDATOR_2,$VALIDATOR_3,$VALIDATOR_4,$VALIDATOR_5]")
STAKING_VAULT_PROXY_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" $STAKING_VAULT_IMPL $STAKING_VAULT_INIT_DATA)
STAKING_VAULT_PROXY_INIT_CODE=$(cast concat-hex $PROXY_BYTECODE $STAKING_VAULT_PROXY_CONSTRUCTOR_ARGS)
STAKING_VAULT_PROXY_RESULT=$(cast create2 --starts-with 8888888 --init-code $STAKING_VAULT_PROXY_INIT_CODE)
STAKING_VAULT_PROXY=$(echo "$STAKING_VAULT_PROXY_RESULT" | grep "Address:" | awk '{print $2}')
STAKING_VAULT_PROXY_SALT=$(echo "$STAKING_VAULT_PROXY_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $STAKING_VAULT_PROXY"
echo "   Salt: $STAKING_VAULT_PROXY_SALT"
echo ""

# 4. StakingVaultManager Proxy
echo "4/4 Grinding StakingVaultManager Proxy..."
STAKING_VAULT_MANAGER_INIT_DATA=$(cast calldata "initialize(address,address,address,address,uint256,uint256,uint256,uint256)" \
  $ROLE_REGISTRY_PROXY \
  $VHYPE_PROXY \
  $STAKING_VAULT_PROXY \
  $VALIDATOR \
  $MIN_STAKE_BALANCE \
  $MIN_DEPOSIT \
  $MIN_WITHDRAW \
  $MAX_WITHDRAW)
STAKING_VAULT_MANAGER_PROXY_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,bytes)" $STAKING_VAULT_MANAGER_IMPL $STAKING_VAULT_MANAGER_INIT_DATA)
STAKING_VAULT_MANAGER_PROXY_INIT_CODE=$(cast concat-hex $PROXY_BYTECODE $STAKING_VAULT_MANAGER_PROXY_CONSTRUCTOR_ARGS)
STAKING_VAULT_MANAGER_PROXY_RESULT=$(cast create2 --starts-with 8888888 --init-code $STAKING_VAULT_MANAGER_PROXY_INIT_CODE)
STAKING_VAULT_MANAGER_PROXY=$(echo "$STAKING_VAULT_MANAGER_PROXY_RESULT" | grep "Address:" | awk '{print $2}')
STAKING_VAULT_MANAGER_PROXY_SALT=$(echo "$STAKING_VAULT_MANAGER_PROXY_RESULT" | grep "Salt:" | awk '{print $2}')
echo "   Address: $STAKING_VAULT_MANAGER_PROXY"
echo "   Salt: $STAKING_VAULT_MANAGER_PROXY_SALT"
echo ""

# ============================================
# STEP 3: Save Results
# ============================================
echo "=== STEP 3: Saving Results ==="
echo ""

# Save to .env file
cat > .env.salts << EOF
# CREATE2 Salts - Generated on $(date)
# Configuration: Owner=$OWNER, Mainnet, Production

# Implementation Salts
ROLE_REGISTRY_IMPL_SALT=$ROLE_REGISTRY_IMPL_SALT
VHYPE_IMPL_SALT=$VHYPE_IMPL_SALT
STAKING_VAULT_IMPL_SALT=$STAKING_VAULT_IMPL_SALT
STAKING_VAULT_MANAGER_IMPL_SALT=$STAKING_VAULT_MANAGER_IMPL_SALT

# Proxy Salts
ROLE_REGISTRY_PROXY_SALT=$ROLE_REGISTRY_PROXY_SALT
VHYPE_PROXY_SALT=$VHYPE_PROXY_SALT
STAKING_VAULT_PROXY_SALT=$STAKING_VAULT_PROXY_SALT
STAKING_VAULT_MANAGER_PROXY_SALT=$STAKING_VAULT_MANAGER_PROXY_SALT

# Expected Addresses (for verification)
ROLE_REGISTRY_IMPL=$ROLE_REGISTRY_IMPL
VHYPE_IMPL=$VHYPE_IMPL
STAKING_VAULT_IMPL=$STAKING_VAULT_IMPL
STAKING_VAULT_MANAGER_IMPL=$STAKING_VAULT_MANAGER_IMPL

ROLE_REGISTRY_PROXY=$ROLE_REGISTRY_PROXY
VHYPE_PROXY=$VHYPE_PROXY
STAKING_VAULT_PROXY=$STAKING_VAULT_PROXY
STAKING_VAULT_MANAGER_PROXY=$STAKING_VAULT_MANAGER_PROXY
EOF

echo "Results saved to .env.salts"
echo ""

# Print summary
echo "======================================"
echo "SUMMARY - All Addresses & Salts"
echo "======================================"
echo ""
echo "IMPLEMENTATIONS:"
echo "  RoleRegistry:         $ROLE_REGISTRY_IMPL"
echo "  VHYPE:                $VHYPE_IMPL"
echo "  StakingVault:         $STAKING_VAULT_IMPL"
echo "  StakingVaultManager:  $STAKING_VAULT_MANAGER_IMPL"
echo ""
echo "PROXIES (User-facing):"
echo "  RoleRegistry:         $ROLE_REGISTRY_PROXY"
echo "  VHYPE:                $VHYPE_PROXY"
echo "  StakingVault:         $STAKING_VAULT_PROXY"
echo "  StakingVaultManager:  $STAKING_VAULT_MANAGER_PROXY"
echo ""
echo "======================================"
echo "Next Steps:"
echo "1. Review .env.salts file"
echo "2. Update your .env file with these salts"
echo "3. Run DeployContracts.s.sol to deploy contracts with these salts"
echo "======================================"