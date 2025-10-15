// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {console} from "forge-std/console.sol";

contract DeployContracts is Script {
    struct VaultConfig {
        uint256 minimumStakeBalance;
        uint256 minimumDepositAmount;
        uint256 minimumWithdrawAmount;
        uint256 maximumWithdrawAmount;
    }

    // ============================================
    // Salts (loaded from .env.salts)
    // ============================================

    // Implementation Salts
    bytes32 ROLE_REGISTRY_IMPL_SALT;
    bytes32 VHYPE_IMPL_SALT;
    bytes32 STAKING_VAULT_IMPL_SALT;
    bytes32 STAKING_VAULT_MANAGER_IMPL_SALT;

    // Proxy Salts
    bytes32 ROLE_REGISTRY_PROXY_SALT;
    bytes32 VHYPE_PROXY_SALT;
    bytes32 STAKING_VAULT_PROXY_SALT;
    bytes32 STAKING_VAULT_MANAGER_PROXY_SALT;

    // Expected Addresses (for verification)
    address EXPECTED_ROLE_REGISTRY_IMPL;
    address EXPECTED_VHYPE_IMPL;
    address EXPECTED_STAKING_VAULT_IMPL;
    address EXPECTED_STAKING_VAULT_MANAGER_IMPL;
    address EXPECTED_ROLE_REGISTRY_PROXY;
    address EXPECTED_VHYPE_PROXY;
    address EXPECTED_STAKING_VAULT_PROXY;
    address EXPECTED_STAKING_VAULT_MANAGER_PROXY;

    // ============================================
    // Validators
    // ============================================

    // Mainnet validators
    address public constant VALIDATOR_MAINNET_HYPER_FOUNDATION_1 = 0x5aC99df645F3414876C816Caa18b2d234024b487;
    address public constant VALIDATOR_MAINNET_HYPER_FOUNDATION_2 = 0xA82FE73bBD768bC15D1eF2F6142a21fF8bD762AD;
    address public constant VALIDATOR_MAINNET_HYPER_FOUNDATION_3 = 0x80f0CD23DA5BF3a0101110cfD0F89C8a69a1384d;
    address public constant VALIDATOR_MAINNET_HYPER_FOUNDATION_4 = 0xdF35aee8ef5658686142ACd1E5AB5DBcDF8c51e8;
    address public constant VALIDATOR_MAINNET_HYPER_FOUNDATION_5 = 0x66Be52ec79F829Cc88E5778A255E2cb9492798fd;

    // Testnet validators
    address public constant VALIDATOR_TESTNET_HYPURR = 0x946bF3135c7D15E4462b510f74B6e304AABb5B21;

    function run() public {
        // Load salts and addresses from environment
        loadSaltsAndAddresses();

        address owner = vm.envAddress("OWNER");
        require(owner != address(0), "Owner address is not set");
        console.log("Owner:", owner);

        bool isTestnet = vm.envBool("IS_TESTNET");
        bool isTestVault = vm.envBool("IS_TEST_VAULT");

        console.log("===========================================");
        console.log("Deploying with CREATE2 Deterministic Salts");
        console.log("===========================================");
        console.log("");

        vm.startBroadcast();

        // Deploy in dependency order
        address roleRegistryImpl = deployRoleRegistryImplementation();
        address vhypeImpl = deployVHYPEImplementation();
        address stakingVaultImpl = deployStakingVaultImplementation(isTestnet);
        address stakingVaultManagerImpl = deployStakingVaultManagerImplementation();

        console.log("");

        address roleRegistryProxy = deployRoleRegistryProxy(roleRegistryImpl, owner);
        address vhypeProxy = deployVHYPEProxy(vhypeImpl, roleRegistryProxy);
        address stakingVaultProxy = deployStakingVaultProxy(stakingVaultImpl, isTestnet, roleRegistryProxy);
        address stakingVaultManagerProxy = deployStakingVaultManagerProxy(
            stakingVaultManagerImpl, isTestnet, isTestVault, roleRegistryProxy, vhypeProxy, stakingVaultProxy
        );

        console.log("");
        console.log("Granting MANAGER_ROLE to StakingVaultManager...");
        RoleRegistry(roleRegistryProxy)
            .grantRole(RoleRegistry(roleRegistryProxy).MANAGER_ROLE(), stakingVaultManagerProxy);
        console.log("MANAGER_ROLE granted!");

        vm.stopBroadcast();

        console.log("");
        console.log("===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("PROXIES (User-facing addresses):");
        console.log("  RoleRegistry:        ", roleRegistryProxy);
        console.log("  VHYPE:               ", vhypeProxy);
        console.log("  StakingVault:        ", stakingVaultProxy);
        console.log("  StakingVaultManager: ", stakingVaultManagerProxy);
        console.log("");
        console.log("IMPLEMENTATIONS:");
        console.log("  RoleRegistry:        ", roleRegistryImpl);
        console.log("  VHYPE:               ", vhypeImpl);
        console.log("  StakingVault:        ", stakingVaultImpl);
        console.log("  StakingVaultManager: ", stakingVaultManagerImpl);
        console.log("===========================================");
    }

    // ============================================
    // Load Salts and Addresses from Environment
    // ============================================

    function loadSaltsAndAddresses() internal {
        console.log("Loading salts and addresses from .env.salts...");

        // Load Implementation Salts
        ROLE_REGISTRY_IMPL_SALT = vm.envBytes32("ROLE_REGISTRY_IMPL_SALT");
        VHYPE_IMPL_SALT = vm.envBytes32("VHYPE_IMPL_SALT");
        STAKING_VAULT_IMPL_SALT = vm.envBytes32("STAKING_VAULT_IMPL_SALT");
        STAKING_VAULT_MANAGER_IMPL_SALT = vm.envBytes32("STAKING_VAULT_MANAGER_IMPL_SALT");

        // Load Proxy Salts
        ROLE_REGISTRY_PROXY_SALT = vm.envBytes32("ROLE_REGISTRY_PROXY_SALT");
        VHYPE_PROXY_SALT = vm.envBytes32("VHYPE_PROXY_SALT");
        STAKING_VAULT_PROXY_SALT = vm.envBytes32("STAKING_VAULT_PROXY_SALT");
        STAKING_VAULT_MANAGER_PROXY_SALT = vm.envBytes32("STAKING_VAULT_MANAGER_PROXY_SALT");

        // Load Expected Addresses
        EXPECTED_ROLE_REGISTRY_IMPL = vm.envAddress("ROLE_REGISTRY_IMPL");
        EXPECTED_VHYPE_IMPL = vm.envAddress("VHYPE_IMPL");
        EXPECTED_STAKING_VAULT_IMPL = vm.envAddress("STAKING_VAULT_IMPL");
        EXPECTED_STAKING_VAULT_MANAGER_IMPL = vm.envAddress("STAKING_VAULT_MANAGER_IMPL");
        EXPECTED_ROLE_REGISTRY_PROXY = vm.envAddress("ROLE_REGISTRY_PROXY");
        EXPECTED_VHYPE_PROXY = vm.envAddress("VHYPE_PROXY");
        EXPECTED_STAKING_VAULT_PROXY = vm.envAddress("STAKING_VAULT_PROXY");
        EXPECTED_STAKING_VAULT_MANAGER_PROXY = vm.envAddress("STAKING_VAULT_MANAGER_PROXY");

        console.log("Salts and addresses loaded successfully!");
        console.log("");
    }

    // ============================================
    // Implementation Deployments
    // ============================================

    function deployRoleRegistryImplementation() internal returns (address) {
        console.log("Deploying RoleRegistry Implementation with CREATE2...");
        RoleRegistry impl = new RoleRegistry{salt: ROLE_REGISTRY_IMPL_SALT}();

        require(address(impl) == EXPECTED_ROLE_REGISTRY_IMPL, "RoleRegistry impl address mismatch!");

        console.log("  Address:", address(impl));
        console.log("  Salt:   ", vm.toString(ROLE_REGISTRY_IMPL_SALT));
        console.log("  Address verified!");
        return address(impl);
    }

    function deployVHYPEImplementation() internal returns (address) {
        console.log("Deploying VHYPE Implementation with CREATE2...");
        VHYPE impl = new VHYPE{salt: VHYPE_IMPL_SALT}();

        require(address(impl) == EXPECTED_VHYPE_IMPL, "VHYPE impl address mismatch!");

        console.log("  Address:", address(impl));
        console.log("  Salt:   ", vm.toString(VHYPE_IMPL_SALT));
        console.log("  Address verified!");
        return address(impl);
    }

    function deployStakingVaultImplementation(bool isTestnet) internal returns (address) {
        console.log("Deploying StakingVault Implementation with CREATE2...");
        StakingVault impl = new StakingVault{salt: STAKING_VAULT_IMPL_SALT}(getHypeTokenId(isTestnet));

        require(address(impl) == EXPECTED_STAKING_VAULT_IMPL, "StakingVault impl address mismatch!");

        console.log("  Address:", address(impl));
        console.log("  Salt:   ", vm.toString(STAKING_VAULT_IMPL_SALT));
        console.log("  Address verified!");
        return address(impl);
    }

    function deployStakingVaultManagerImplementation() internal returns (address) {
        console.log("Deploying StakingVaultManager Implementation with CREATE2...");
        StakingVaultManager impl = new StakingVaultManager{salt: STAKING_VAULT_MANAGER_IMPL_SALT}();

        require(address(impl) == EXPECTED_STAKING_VAULT_MANAGER_IMPL, "StakingVaultManager impl address mismatch!");

        console.log("  Address:", address(impl));
        console.log("  Salt:   ", vm.toString(STAKING_VAULT_MANAGER_IMPL_SALT));
        console.log("  Address verified!");
        return address(impl);
    }

    // ============================================
    // Proxy Deployments
    // ============================================

    function deployRoleRegistryProxy(address impl, address owner) internal returns (address) {
        console.log("Deploying RoleRegistry Proxy with CREATE2...");
        bytes memory initData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);

        ERC1967Proxy proxy = new ERC1967Proxy{salt: ROLE_REGISTRY_PROXY_SALT}(impl, initData);

        require(address(proxy) == EXPECTED_ROLE_REGISTRY_PROXY, "RoleRegistry proxy address mismatch!");

        console.log("  Address:", address(proxy));
        console.log("  Salt:   ", vm.toString(ROLE_REGISTRY_PROXY_SALT));
        console.log("  Address verified!");
        return address(proxy);
    }

    function deployVHYPEProxy(address impl, address roleRegistry) internal returns (address) {
        console.log("Deploying VHYPE Proxy with CREATE2...");
        bytes memory initData = abi.encodeWithSelector(VHYPE.initialize.selector, roleRegistry);

        ERC1967Proxy proxy = new ERC1967Proxy{salt: VHYPE_PROXY_SALT}(impl, initData);

        require(address(proxy) == EXPECTED_VHYPE_PROXY, "VHYPE proxy address mismatch!");

        console.log("  Address:", address(proxy));
        console.log("  Salt:   ", vm.toString(VHYPE_PROXY_SALT));
        console.log("  Address verified!");
        return address(proxy);
    }

    function deployStakingVaultProxy(address impl, bool isTestnet, address roleRegistry) internal returns (address) {
        console.log("Deploying StakingVault Proxy with CREATE2...");
        bytes memory initData =
            abi.encodeWithSelector(StakingVault.initialize.selector, roleRegistry, getWhitelistedValidators(isTestnet));

        ERC1967Proxy proxy = new ERC1967Proxy{salt: STAKING_VAULT_PROXY_SALT}(impl, initData);

        require(address(proxy) == EXPECTED_STAKING_VAULT_PROXY, "StakingVault proxy address mismatch!");

        console.log("  Address:", address(proxy));
        console.log("  Salt:   ", vm.toString(STAKING_VAULT_PROXY_SALT));
        console.log("  Address verified!");
        return address(proxy);
    }

    function deployStakingVaultManagerProxy(
        address impl,
        bool isTestnet,
        bool isTestVault,
        address roleRegistry,
        address vhype,
        address stakingVault
    ) internal returns (address) {
        console.log("Deploying StakingVaultManager Proxy with CREATE2...");
        VaultConfig memory config = getVaultConfig(isTestnet, isTestVault);

        bytes memory initData = abi.encodeWithSelector(
            StakingVaultManager.initialize.selector,
            roleRegistry,
            vhype,
            stakingVault,
            getValidator(isTestnet),
            config.minimumStakeBalance,
            config.minimumDepositAmount,
            config.minimumWithdrawAmount,
            config.maximumWithdrawAmount
        );

        ERC1967Proxy proxy = new ERC1967Proxy{salt: STAKING_VAULT_MANAGER_PROXY_SALT}(impl, initData);

        require(address(proxy) == EXPECTED_STAKING_VAULT_MANAGER_PROXY, "StakingVaultManager proxy address mismatch!");

        console.log("  Address:", address(proxy));
        console.log("  Salt:   ", vm.toString(STAKING_VAULT_MANAGER_PROXY_SALT));
        console.log("  Address verified!");
        return address(proxy);
    }

    // ============================================
    // Helper Functions
    // ============================================

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
            return 0.5 * 1e18; // 0.5 HYPE
        }
    }

    function getMaximumWithdrawAmount(bool isTestnet, bool isTestVault) internal pure returns (uint256) {
        if (isTestnet || isTestVault) {
            return 0.02 * 1e18; // 0.02 HYPE
        } else {
            return 10_000 * 1e18; // 10k HYPE
        }
    }

    function getVaultConfig(bool isTestnet, bool isTestVault) internal pure returns (VaultConfig memory) {
        return VaultConfig({
            minimumStakeBalance: getMinimumStakeBalance(isTestnet, isTestVault),
            minimumDepositAmount: getMinimumDepositAmount(isTestnet, isTestVault),
            minimumWithdrawAmount: getMinimumWithdrawAmount(isTestnet, isTestVault),
            maximumWithdrawAmount: getMaximumWithdrawAmount(isTestnet, isTestVault)
        });
    }

    function getValidator(bool isTestnet) internal pure returns (address) {
        if (isTestnet) {
            return VALIDATOR_TESTNET_HYPURR;
        } else {
            return VALIDATOR_MAINNET_HYPER_FOUNDATION_1;
        }
    }

    function getWhitelistedValidators(bool isTestnet) internal pure returns (address[] memory) {
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
