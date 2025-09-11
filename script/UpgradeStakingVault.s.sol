// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract UpgradeStakingVault is Script {
    function run() public {
        address stakingVaultAddress = vm.envAddress("STAKING_VAULT");
        require(stakingVaultAddress != address(0), "StakingVault address is not set");

        vm.startBroadcast();

        StakingVault proxy = StakingVault(payable(stakingVaultAddress));
        StakingVault newImplementation = new StakingVault();
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("StakingVault proxy address:", address(proxy));
        console.log("StakingVault new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
