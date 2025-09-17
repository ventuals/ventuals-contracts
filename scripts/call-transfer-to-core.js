require("dotenv").config();
const { ethers } = require("ethers");

// Contract configuration
const CONTRACT_ADDRESS = process.env.GENESIS_VAULT_MANAGER;
const STAKING_VAULT_ADDRESS = process.env.STAKING_VAULT;
const IS_TESTNET = process.env.IS_TESTNET !== "false"; // Default to true if not specified

// Contract ABI - only the functions we need
const CONTRACT_ABI = [
  {
    inputs: [],
    name: "transferToCoreAndDelegate",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "transferToCoreAndDelegate",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

async function main() {
  try {
    // Validate required environment variables
    if (!CONTRACT_ADDRESS) {
      throw new Error("GENESIS_VAULT_MANAGER environment variable is required");
    }
    if (!STAKING_VAULT_ADDRESS) {
      throw new Error("STAKING_VAULT environment variable is required");
    }

    // Parse command line arguments
    const args = process.argv.slice(2);
    const transferAmount = args[0] ? ethers.parseEther(args[0]) : null;

    // Set up provider based on network
    const rpcUrl = IS_TESTNET
      ? "https://rpc.hyperliquid-testnet.xyz/evm"
      : "https://rpc.hyperliquid.xyz/evm";

    const provider = new ethers.JsonRpcProvider(rpcUrl);

    // Set up wallet
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
      throw new Error("PRIVATE_KEY environment variable is required");
    }
    const wallet = new ethers.Wallet(privateKey, provider);

    // Connect to the GenesisVaultManager contract
    const contract = new ethers.Contract(
      CONTRACT_ADDRESS,
      CONTRACT_ABI,
      wallet
    );

    console.log(`🌐 Network: ${IS_TESTNET ? "Testnet" : "Mainnet"}`);
    console.log(
      `📋 Calling transferToCoreAndDelegate() on GenesisVaultManager: ${CONTRACT_ADDRESS}`
    );
    console.log(`👤 Using wallet: ${wallet.address}`);

    let initialStakingVaultBalance = null;
    if (transferAmount) {
      console.log(
        `💰 Transfer amount: ${ethers.formatEther(transferAmount)} HYPE`
      );
    } else {
      // Check the EVM balance of the StakingVault when transferring all
      initialStakingVaultBalance = await provider.getBalance(
        STAKING_VAULT_ADDRESS
      );
      console.log(
        `💰 Transfer amount: All available balance (${ethers.formatEther(
          initialStakingVaultBalance
        )} HYPE)`
      );
    }

    // Get gas price
    const feeData = await provider.getFeeData();
    console.log(
      `⛽ Gas price: ${ethers.formatUnits(feeData.gasPrice, "gwei")} gwei`
    );

    // Call transferToCoreAndDelegate function
    console.log("\n🚀 Sending transferToCoreAndDelegate transaction...");

    let tx;
    if (transferAmount) {
      // Call with specific amount
      tx = await contract["transferToCoreAndDelegate(uint256)"](
        transferAmount,
        {
          gasLimit: 2000000, // Conservative gas limit for complex operation
          gasPrice: feeData.gasPrice,
        }
      );
    } else {
      // Call without amount (transfers all)
      tx = await contract["transferToCoreAndDelegate()"]({
        gasLimit: 2000000, // Conservative gas limit for complex operation
        gasPrice: feeData.gasPrice,
      });
    }

    console.log(`📝 Transaction hash: ${tx.hash}`);
    console.log("⏳ Waiting for transaction to be mined...");

    // Wait for transaction to be mined
    const receipt = await tx.wait();

    console.log(`✅ Transaction confirmed in block ${receipt.blockNumber}`);
    console.log(`⛽ Gas used: ${receipt.gasUsed.toString()}`);

    console.log("\n🎉 Successfully transferred HYPE to Core and delegated!");
    if (transferAmount) {
      console.log(
        `Amount transferred: ${ethers.formatEther(transferAmount)} HYPE`
      );
    } else {
      console.log(
        `Amount transferred: ${ethers.formatEther(
          initialStakingVaultBalance
        )} HYPE`
      );
    }
  } catch (error) {
    console.error(
      "❌ Error calling transferToCoreAndDelegate():",
      error.message
    );
    if (error.reason) {
      console.error("Reason:", error.reason);
    }
    if (error.message.includes("AccessControlUnauthorizedAccount")) {
      console.error(
        "💡 Make sure your wallet has the OPERATOR role on the GenesisVaultManager"
      );
    }
    process.exit(1);
  }
}

// Run the script
if (require.main === module) {
  console.log("Usage:");
  console.log(
    "  npm run transfer-to-core                   # Transfer all available balance"
  );
  console.log(
    "  npm run transfer-to-core 1.5               # Transfer specific amount (1.5 HYPE)"
  );
  console.log(
    "  node scripts/call-transfer-to-core.js      # Transfer all available balance"
  );
  console.log(
    "  node scripts/call-transfer-to-core.js 1.5  # Transfer specific amount (1.5 HYPE)"
  );
  console.log("");
  main();
}

module.exports = { main };
