require("dotenv").config();
const { ethers } = require("ethers");

// Contract configuration
const CONTRACT_ADDRESS = process.env.GENESIS_VAULT_MANAGER;
const DEPOSIT_AMOUNT = ethers.parseEther("0.01"); // 0.01 HYPE
const IS_TESTNET = process.env.IS_TESTNET !== "false"; // Default to true if not specified

// Contract ABI - only the deposit function we need
const CONTRACT_ABI = [
  {
    inputs: [],
    name: "deposit",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
];

async function main() {
  try {
    // Validate required environment variables
    if (!CONTRACT_ADDRESS) {
      throw new Error("GENESIS_VAULT_MANAGER environment variable is required");
    }

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
      `📋 Calling deposit() on GenesisVaultManager: ${CONTRACT_ADDRESS}`
    );
    console.log(`👤 Using wallet: ${wallet.address}`);
    console.log(
      `💰 Deposit amount: ${ethers.formatEther(DEPOSIT_AMOUNT)} HYPE`
    );

    // Get current balance
    const balance = await provider.getBalance(wallet.address);
    console.log(`💳 Wallet balance: ${ethers.formatEther(balance)} HYPE`);

    if (balance < DEPOSIT_AMOUNT) {
      throw new Error("Insufficient balance for deposit");
    }

    // Get gas price
    const feeData = await provider.getFeeData();
    console.log(
      `⛽ Gas price: ${ethers.formatUnits(feeData.gasPrice, "gwei")} gwei`
    );

    // Call deposit function
    console.log("\n🚀 Sending deposit transaction...");

    const tx = await contract.deposit({
      value: DEPOSIT_AMOUNT,
      gasLimit: 800000, // Conservative gas limit
      gasPrice: feeData.gasPrice,
    });

    console.log(`📝 Transaction hash: ${tx.hash}`);
    console.log("⏳ Waiting for transaction to be mined...");

    // Wait for transaction to be mined
    const receipt = await tx.wait();

    console.log(`✅ Transaction confirmed in block ${receipt.blockNumber}`);
    console.log(`⛽ Gas used: ${receipt.gasUsed.toString()}`);

    console.log("\n🎉 Successfully deposited HYPE to GenesisVaultManager!");
    console.log(`Amount deposited: ${ethers.formatEther(DEPOSIT_AMOUNT)} HYPE`);
  } catch (error) {
    console.error("❌ Error calling deposit():", error.message);
    if (error.reason) {
      console.error("Reason:", error.reason);
    }
    process.exit(1);
  }
}

// Run the script
if (require.main === module) {
  main();
}

module.exports = { main };
