// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {console} from "forge-std/console.sol";

contract DeployContracts is Script {
    // Mainnet validators
    address public immutable VALIDATOR_MAINNET_HYPER_FOUNDATION_1 = 0x5aC99df645F3414876C816Caa18b2d234024b487;
    address public immutable VALIDATOR_MAINNET_HYPER_FOUNDATION_2 = 0xA82FE73bBD768bC15D1eF2F6142a21fF8bD762AD;
    address public immutable VALIDATOR_MAINNET_HYPER_FOUNDATION_3 = 0x80f0CD23DA5BF3a0101110cfD0F89C8a69a1384d;
    address public immutable VALIDATOR_MAINNET_HYPER_FOUNDATION_4 = 0xdF35aee8ef5658686142ACd1E5AB5DBcDF8c51e8;
    address public immutable VALIDATOR_MAINNET_HYPER_FOUNDATION_5 = 0x66Be52ec79F829Cc88E5778A255E2cb9492798fd;

    // Testnet validators
    address public immutable VALIDATOR_TESTNET_HYPURR = 0x946bF3135c7D15E4462b510f74B6e304AABb5B21;

    function run() public {
        address owner = vm.envAddress("OWNER");
        require(owner != address(0), "Owner address is not set");
        console.log("Owner:", owner);
        bool isTestnet = vm.envBool("IS_TESTNET");
        bool isTestVault = vm.envBool("IS_TEST_VAULT");

        vm.startBroadcast();

        address roleRegistryProxy = deployRoleRegistry(owner);
        address vhypeProxy = deployVHYPE(roleRegistryProxy);
        address stakingVaultProxy = deployStakingVault(isTestnet, roleRegistryProxy);
        address stakingVaultManagerProxy =
            deployStakingVaultManager(isTestnet, isTestVault, roleRegistryProxy, vhypeProxy, stakingVaultProxy);

        console.log("Granting MANAGER_ROLE to StakingVaultManager...");
        RoleRegistry(roleRegistryProxy).grantRole(
            RoleRegistry(roleRegistryProxy).MANAGER_ROLE(), stakingVaultManagerProxy
        );
        console.log("MANAGER_ROLE granted to StakingVaultManager:", stakingVaultManagerProxy);

        vm.stopBroadcast();
    }

    function deployRoleRegistry(address owner) internal returns (address) {
        console.log("Deploying RoleRegistry...");
        RoleRegistry roleRegistryImplementation = new RoleRegistry();
        bytes memory roleRegistryInitData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner /* Owner */ );
        ERC1967Proxy roleRegistryProxy = new ERC1967Proxy(address(roleRegistryImplementation), roleRegistryInitData);
        console.log("RoleRegistry (proxy) deployed to:", address(roleRegistryProxy));
        console.log("RoleRegistry (implementation) deployed to:", address(roleRegistryImplementation));
        return address(roleRegistryProxy);
    }

    function deployVHYPE(address roleRegistryProxy) internal returns (address) {
        console.log("Deploying VHYPE...");
        VHYPE vhypeImplementation = new VHYPE();
        bytes memory vhypeInitData =
            abi.encodeWithSelector(VHYPE.initialize.selector, address(roleRegistryProxy) /* RoleRegistry */ );
        ERC1967Proxy vhypeProxy = new ERC1967Proxy(address(vhypeImplementation), vhypeInitData);
        console.log("VHYPE (proxy) deployed to:", address(vhypeProxy));
        console.log("VHYPE (implementation) deployed to:", address(vhypeImplementation));
        return address(vhypeProxy);
    }

    function deployStakingVault(bool isTestnet, address roleRegistryProxy) internal returns (address) {
        console.log("Deploying StakingVault...");
        StakingVault stakingVaultImplementation = new StakingVault(getHypeTokenId(isTestnet));
        bytes memory stakingVaultInitData = abi.encodeWithSelector(
            StakingVault.initialize.selector,
            address(roleRegistryProxy), /* RoleRegistry */
            getWhitelistedValidators(isTestnet) /* Whitelisted validators */
        );
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        console.log("StakingVault (proxy) deployed to:", address(stakingVaultProxy));
        console.log("StakingVault (implementation) deployed to:", address(stakingVaultImplementation));
        return address(stakingVaultProxy);
    }

    function deployStakingVaultManager(
        bool isTestnet,
        bool isTestVault,
        address roleRegistryProxy,
        address vhypeProxy,
        address stakingVaultProxy
    ) internal returns (address) {
        console.log("Deploying StakingVaultManager...");
        StakingVaultManager stakingVaultManagerImplementation = new StakingVaultManager();
        bytes memory stakingVaultManagerInitData = abi.encodeWithSelector(
            StakingVaultManager.initialize.selector,
            address(roleRegistryProxy), /* RoleRegistry */
            address(vhypeProxy), /* VHYPE */
            address(stakingVaultProxy), /* StakingVault */
            getValidator(isTestnet), /* Default validator */
            getMinimumStakeBalance(isTestnet, isTestVault), /* Minimum stake balance */
            getMinimumDepositAmount(isTestnet, isTestVault), /* Minimum deposit amount */
            getMinimumWithdrawAmount(isTestnet, isTestVault) /* Minimum withdraw amount */
        );
        ERC1967Proxy stakingVaultManagerProxy =
            new ERC1967Proxy(address(stakingVaultManagerImplementation), stakingVaultManagerInitData);
        console.log("StakingVaultManager (proxy) deployed to:", address(stakingVaultManagerProxy));
        console.log("StakingVaultManager (implementation) deployed to:", address(stakingVaultManagerImplementation));
        return address(stakingVaultManagerProxy);
    }

    function getHypeTokenId(bool isTestnet) internal pure returns (uint64) {
        // https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids
        if (isTestnet) {
            return 1105;
        } else {
            return 150;
        }
    }

    function getMinimumStakeBalance(bool isTestnet, bool isTestVault) internal pure returns (uint256) {
        if (isTestnet || isTestVault) {
            return 1 * 1e18; // 1 HYPE
        } else {
            return 500_000 * 1e18; // 500k HYPE
        }
    }

    function getMinimumDepositAmount(bool isTestnet, bool isTestVault) internal pure returns (uint256) {
        if (isTestnet || isTestVault) {
            return 0.01 * 1e18; // 0.01 HYPE
        } else {
            return 1 * 1e18; // 1 HYPE
        }
    }

    function getMinimumWithdrawAmount(bool isTestnet, bool isTestVault) internal pure returns (uint256) {
        if (isTestnet || isTestVault) {
            return 0.01 * 1e18; // 0.01 HYPE
        } else {
            return 1 * 1e18; // 1 HYPE
        }
    }

    function getValidator(bool isTestnet) internal view returns (address) {
        if (isTestnet) {
            return VALIDATOR_TESTNET_HYPURR;
        } else {
            return VALIDATOR_MAINNET_HYPER_FOUNDATION_1;
        }
    }

    function getWhitelistedValidators(bool isTestnet) internal view returns (address[] memory) {
        if (isTestnet) {
            address[] memory validators = new address[](1);
            validators[0] = VALIDATOR_TESTNET_HYPURR;
            return validators;
        } else {
            address[] memory validators = new address[](5);
            validators[0] = VALIDATOR_MAINNET_HYPER_FOUNDATION_1;
            validators[1] = VALIDATOR_MAINNET_HYPER_FOUNDATION_2;
            validators[2] = VALIDATOR_MAINNET_HYPER_FOUNDATION_3;
            validators[3] = VALIDATOR_MAINNET_HYPER_FOUNDATION_4;
            validators[4] = VALIDATOR_MAINNET_HYPER_FOUNDATION_5;
            return validators;
        }
    }
}
