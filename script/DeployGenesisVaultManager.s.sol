// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployGenesisVaultManager is Script {
    function run() public {
        address roleRegistry = vm.envAddress("ROLE_REGISTRY");
        address vHYPE = vm.envAddress("VHYPE");
        address stakingVault = vm.envAddress("STAKING_VAULT");
        uint64 hypeTokenId = vm.envUint("HYPE_TOKEN_ID");
        require(roleRegistry != address(0), "RoleRegistry address is not set");
        require(vHYPE != address(0), "vHYPE address is not set");
        require(stakingVault != address(0), "StakingVault address is not set");
        require(hypeTokenId != 0, "HYPE_TOKEN_ID is not set");

        vm.startBroadcast();

        GenesisVaultManager implementation = new GenesisVaultManager(hypeTokenId);
        bytes memory initData = abi.encodeWithSelector(
            GenesisVaultManager.initialize.selector,
            roleRegistry,
            vHYPE,
            stakingVault,
            1_200_000 * 1e18,
            0x946bF3135c7D15E4462b510f74B6e304AABb5B21
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Using RoleRegistry at:", roleRegistry);
        console.log("GenesisVaultManager (proxy) deployed to:", address(proxy));
        console.log("GenesisVaultManager (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
