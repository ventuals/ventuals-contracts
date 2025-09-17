// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployGenesisVaultManager is Script {
    function run() public {
        address roleRegistry = vm.envAddress("ROLE_REGISTRY");
        /// forge-lint: disable-next-line(mixed-case-variable)
        address vHYPE = vm.envAddress("VHYPE");
        address stakingVault = vm.envAddress("STAKING_VAULT");
        bool isTestnet = vm.envBool("IS_TESTNET");
        address defaultValidator = vm.envAddress("DEFAULT_VALIDATOR");
        require(roleRegistry != address(0), "RoleRegistry address is not set");
        require(vHYPE != address(0), "vHYPE address is not set");
        require(stakingVault != address(0), "StakingVault address is not set");
        require(defaultValidator != address(0), "DefaultValidator address is not set");

        vm.startBroadcast();

        uint64 hypeTokenId = isTestnet ? 1105 : 150; // https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids
        GenesisVaultManager implementation = new GenesisVaultManager(hypeTokenId);
        bytes memory initData = abi.encodeWithSelector(
            GenesisVaultManager.initialize.selector,
            roleRegistry, /* roleRegistry */
            vHYPE, /* vHYPE */
            stakingVault, /* stakingVault */
            1_200_000 * 1e18, /* vaultCapacity */
            defaultValidator, /* defaultValidator */
            100_000 * 1e18, /* defaultDepositLimit */
            0.01 * 1e18 /* minimumDepositAmount */
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Using RoleRegistry at:", roleRegistry);
        console.log("GenesisVaultManager (proxy) deployed to:", address(proxy));
        console.log("GenesisVaultManager (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
