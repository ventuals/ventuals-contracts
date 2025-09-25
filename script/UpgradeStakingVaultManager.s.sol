// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {console} from "forge-std/console.sol";

contract UpgradeStakingVaultManager is Script {
    function run() public {
        address stakingVaultManagerAddress = vm.envAddress("STAKING_VAULT_MANAGER");
        bool isTestnet = vm.envBool("IS_TESTNET");

        uint64 hypeTokenId = isTestnet ? 1105 : 150; // https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids

        vm.startBroadcast();

        StakingVaultManager proxy = StakingVaultManager(payable(stakingVaultManagerAddress));
        StakingVaultManager newImplementation = new StakingVaultManager(hypeTokenId);
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("StakingVaultManager proxy address:", address(proxy));
        console.log("StakingVaultManager new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
