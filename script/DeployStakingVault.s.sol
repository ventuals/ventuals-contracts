// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployStakingVault is Script {
    function run() public {
        address roleRegistry = vm.envAddress("ROLE_REGISTRY");
        require(roleRegistry != address(0), "RoleRegistry address is not set");

        bool isTestnet = vm.envBool("IS_TESTNET");
        uint64 hypeTokenId = isTestnet ? 1105 : 150; // https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids

        vm.startBroadcast();

        StakingVault implementation = new StakingVault(hypeTokenId);
        bytes memory initData = abi.encodeWithSelector(StakingVault.initialize.selector, roleRegistry);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Using RoleRegistry at:", roleRegistry);
        console.log("StakingVault (proxy) deployed to:", address(proxy));
        console.log("StakingVault (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
