// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {console} from "forge-std/console.sol";

contract UpgradeGenesisVaultManager is Script {
    function run() public {
        address genesisVaultManagerAddress = vm.envAddress("GENESIS_VAULT_MANAGER");

        vm.startBroadcast();

        GenesisVaultManager proxy = GenesisVaultManager(payable(genesisVaultManagerAddress));
        GenesisVaultManager newImplementation = new GenesisVaultManager();
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("GenesisVaultManager proxy address:", address(proxy));
        console.log("GenesisVaultManager new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
