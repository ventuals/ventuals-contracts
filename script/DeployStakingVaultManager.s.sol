// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployStakingVaultManager is Script {
    function run() public {
        address roleRegistry = vm.envAddress("ROLE_REGISTRY");
        /// forge-lint: disable-next-line(mixed-case-variable)
        address vHYPE = vm.envAddress("VHYPE");
        address stakingVault = vm.envAddress("STAKING_VAULT");
        address defaultValidator = vm.envAddress("DEFAULT_VALIDATOR");
        require(roleRegistry != address(0), "RoleRegistry address is not set");
        require(vHYPE != address(0), "vHYPE address is not set");
        require(stakingVault != address(0), "StakingVault address is not set");
        require(defaultValidator != address(0), "DefaultValidator address is not set");

        vm.startBroadcast();

        StakingVaultManager implementation = new StakingVaultManager();
        bytes memory initData = abi.encodeWithSelector(
            StakingVaultManager.initialize.selector,
            roleRegistry, /* roleRegistry */
            vHYPE, /* vHYPE */
            stakingVault, /* stakingVault */
            defaultValidator, /* defaultValidator */
            500_000 * 1e18, /* minimumStakeBalance */
            0.01 * 1e18 /* minimumDepositAmount */
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Using RoleRegistry at:", roleRegistry);
        console.log("StakingVaultManager (proxy) deployed to:", address(proxy));
        console.log("StakingVaultManager (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
