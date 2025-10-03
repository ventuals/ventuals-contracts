// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {console} from "forge-std/console.sol";

contract UpgradeStakingVault is Script {
    function run() public {
        address stakingVaultAddress = vm.envAddress("STAKING_VAULT");
        require(stakingVaultAddress != address(0), "StakingVault address is not set");
        bool isTestnet = vm.envBool("IS_TESTNET");

        uint64 hypeTokenId = isTestnet ? 1105 : 150; // https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids

        vm.startBroadcast();

        StakingVault proxy = StakingVault(payable(stakingVaultAddress));
        StakingVault newImplementation = new StakingVault(hypeTokenId);
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("StakingVault proxy address:", address(proxy));
        console.log("StakingVault new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
