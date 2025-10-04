// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {console} from "forge-std/console.sol";

contract UpgradeStakingVaultManager is Script {
    function run() public {
        address stakingVaultManagerAddress = vm.envAddress("STAKING_VAULT_MANAGER");

        vm.startBroadcast();

        StakingVaultManager proxy = StakingVaultManager(payable(stakingVaultManagerAddress));
        StakingVaultManager newImplementation = new StakingVaultManager();
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("StakingVaultManager proxy address:", address(proxy));
        console.log("StakingVaultManager new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
