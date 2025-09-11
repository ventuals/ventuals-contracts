// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {IStakingVault} from "../src/interfaces/IStakingVault.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Vm} from "forge-std/Vm.sol";

contract GenesisVaultManagerTest is Test {
    GenesisVaultManager genesisVaultManager;
    ProtocolRegistry protocolRegistry;
    VHYPE vHYPE;
    StakingVault stakingVault;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");

    address public defaultValidator = makeAddr("defaultValidator");
    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID
    uint256 public constant VAULT_CAPACITY = 1_200_000 * 1e18; // 1.2M HYPE

    // Events
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);

    function setUp() public {
        // Deploy ProtocolRegistry
        ProtocolRegistry protocolRegistryImplementation = new ProtocolRegistry();
        bytes memory protocolRegistryInitData = abi.encodeWithSelector(ProtocolRegistry.initialize.selector, owner);
        ERC1967Proxy protocolRegistryProxy =
            new ERC1967Proxy(address(protocolRegistryImplementation), protocolRegistryInitData);
        protocolRegistry = ProtocolRegistry(address(protocolRegistryProxy));

        // Deploy vHYPE token
        VHYPE vhypeImplementation = new VHYPE();
        bytes memory vhypeInitData = abi.encodeWithSelector(vHYPE.initialize.selector, address(protocolRegistry));
        ERC1967Proxy vhypeProxy = new ERC1967Proxy(address(vhypeImplementation), vhypeInitData);
        vHYPE = VHYPE(address(vhypeProxy));

        // Deploy StakingVault
        StakingVault stakingVaultImplementation = new StakingVault();
        bytes memory stakingVaultInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(protocolRegistry));
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        stakingVault = StakingVault(payable(stakingVaultProxy));

        // Deploy GenesisVaultManager
        GenesisVaultManager genesisVaultManagerImplementation = new GenesisVaultManager(HYPE_TOKEN_ID);
        bytes memory genesisVaultManagerInitData = abi.encodeWithSelector(
            GenesisVaultManager.initialize.selector,
            address(protocolRegistry),
            address(vHYPE),
            address(stakingVault),
            VAULT_CAPACITY,
            defaultValidator
        );
        ERC1967Proxy genesisVaultManagerProxy =
            new ERC1967Proxy(address(genesisVaultManagerImplementation), genesisVaultManagerInitData);
        genesisVaultManager = GenesisVaultManager(payable(genesisVaultManagerProxy));

        // Setup roles
        vm.startPrank(owner);
        protocolRegistry.grantRole(protocolRegistry.MANAGER_ROLE(), address(genesisVaultManager));
        protocolRegistry.grantRole(protocolRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock HYPE system contract
        MockHypeSystemContract mockHypeSystemContract = new MockHypeSystemContract();
        vm.etch(0x2222222222222222222222222222222222222222, address(mockHypeSystemContract).code);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Initialization                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public view {
        assertEq(address(genesisVaultManager.protocolRegistry()), address(protocolRegistry));
        assertEq(address(genesisVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(genesisVaultManager.stakingVault()), address(stakingVault));
        assertEq(genesisVaultManager.vaultCapacity(), VAULT_CAPACITY);
        assertEq(genesisVaultManager.HYPE_TOKEN_ID(), HYPE_TOKEN_ID);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert("InvalidInitialization()");
        genesisVaultManager.initialize(
            address(protocolRegistry), address(vHYPE), address(stakingVault), VAULT_CAPACITY, defaultValidator
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Tests: Deposit Function               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Deposit_FullDepositIntoEmptyVault() public {
        _mockDelegatorSummary(0);
        _mockSpotBalance(0);

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(depositAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(depositAmount / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that we minted 1:1 vHYPE when vault is empty
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);

        assertEq(userVHYPEBalance, depositAmount);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_PartialDepositIntoEmptyVault() public {
        _mockDelegatorSummary(0);
        _mockSpotBalance(0);

        uint256 depositAmount = 1_500_000 * 1e18; // 1.5M HYPE (more than capacity)

        // Mock staking vault calls
        uint256 expectedStakeAmount = VAULT_CAPACITY;
        _mockAndExpectStakingDepositCall(uint64(expectedStakeAmount / 1e10));
        _mockAndExpectTokenDelegateCall(
            genesisVaultManager.defaultValidator(), uint64(expectedStakeAmount / 1e10), false
        );

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that we minted 1:1 vHYPE when vault is empty
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, VAULT_CAPACITY);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), VAULT_CAPACITY); // Should be exactly equal

        // Check user was refunded the excess
        uint256 expectedRefund = depositAmount - VAULT_CAPACITY;
        assertEq(user.balance, expectedRefund);
    }

    function test_Deposit_FullDepositIntoVaultWithExistingBalance() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k HYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // 1:1 ratio

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(depositAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(depositAmount / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_PartialDepositIntoVaultWithExistingBalance() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // 1:1 ratio

        // Attempt to deposit 1M HYPE; only 700k HYPE will be accepted
        uint256 depositAmount = 1_000_000 * 1e18;

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(700_000 * 1e18 / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(700_000 * 1e18 / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 700_000 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 700_000 * 1e18); // Should be exactly equal

        // Check user was refunded the excess
        assertEq(user.balance, 300_000 * 1e18);
    }

    function test_Deposit_ExchangeRateAboveOneFullDeposit() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 250_000 * 1e18; // 250k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 2

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(depositAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(depositAmount / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount / 2);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateAboveOnePartialDeposit() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 250_000 * 1e18; // 250k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 2

        // Attempt to deposit 1M HYPE; only 700k HYPE will be accepted
        uint256 depositAmount = 1_000_000 * 1e18;

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(700_000 * 1e18 / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(700_000 * 1e18 / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 350_000 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 700_000 * 1e18); // Should be exactly equal

        // Check user was refunded the excess
        assertEq(user.balance, 300_000 * 1e18);
    }

    function test_Deposit_ExchangeRateBelowOneFullDeposit() public {
        uint256 existingBalance = 250_000 * 1e18; // 250k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 0.5

        uint256 depositAmount = 250_000 * 1e18; // 250k HYPE

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(depositAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(depositAmount / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount * 2);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateBelowOnePartialDeposit() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 1_000_000 * 1e18; // 1M vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 0.5

        // Attempt to deposit 1M HYPE; only 700k HYPE will be accepted
        uint256 depositAmount = 1_000_000 * 1e18; // 1M HYPE

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(700_000 * 1e18 / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(700_000 * 1e18 / 1e10), false);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 700_000 * 2 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 700_000 * 1e18); // Should be exactly equal

        // Check user was refunded the excess
        assertEq(user.balance, 300_000 * 1e18);
    }

    function test_Deposit_RevertWhenVaultFull(uint256 depositAmount) public {
        _mockBalancesForExchangeRate(VAULT_CAPACITY, VAULT_CAPACITY);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vm.expectRevert("Vault is full");
        genesisVaultManager.deposit{value: depositAmount}();
    }

    function test_Deposit_ZeroAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        vm.prank(user);
        genesisVaultManager.deposit{value: 0}();

        // No vHYPE should be minted
        assertEq(vHYPE.balanceOf(user), 0);
    }

    function test_Deposit_RevertWhenTransferFails() public {
        // Upgrade staking vault to a version that rejects transfers
        StakingVaultThatRejectsTransfers newImplementation = new StakingVaultThatRejectsTransfers();
        vm.prank(owner);
        stakingVault.upgradeToAndCall(address(newImplementation), "");

        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        vm.deal(user, depositAmount);
        vm.prank(user);
        vm.expectRevert("Transfer failed");
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that no vHYPE was minted
        assertEq(vHYPE.balanceOf(user), 0);
    }

    function test_Deposit_RevertWhenRefundFails() public {
        uint256 existingBalance = 1_000_000 * 1e18; // 1M HYPE
        uint256 existingSupply = 1_000_000 * 1e18; // 1M vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Create a contract that rejects refunds
        ContractThatRejectsTransfers contractThatRejectsTransfers = new ContractThatRejectsTransfers();

        // Mock staking vault calls
        _mockAndExpectStakingDepositCall(uint64(200_000 * 1e18 / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(200_000 * 1e18 / 1e10), false);

        vm.deal(address(contractThatRejectsTransfers), depositAmount);
        vm.prank(address(contractThatRejectsTransfers));
        vm.expectRevert("Refund failed");
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that no vHYPE was minted
        assertEq(vHYPE.balanceOf(address(contractThatRejectsTransfers)), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                Tests: Balance Calculations                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_StakingAccountBalance() public {
        // Mock the delegator summary precompile call
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 1e8, // 1 HYPE in 8 decimals
            undelegated: 5e7, // 0.5 HYPE in 8 decimals
            totalPendingWithdrawal: 2e7, // 0.2 HYPE in 8 decimals
            nPendingWithdrawals: 1
        });
        bytes memory encodedDelegatorSummary = abi.encode(mockDelegatorSummary);
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            encodedDelegatorSummary
        );

        uint256 balance = genesisVaultManager.stakingAccountBalance();
        // (1e8 + 5e7 + 2e7) * 1e10 = 1.7e18
        assertEq(balance, 1.7e18);
    }

    function test_SpotAccountBalance() public {
        // Mock the spot balance precompile call
        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({
            total: 3e8, // 3 HYPE in 8 decimals
            hold: 0,
            entryNtl: 0
        });
        bytes memory encodedSpotBalance = abi.encode(mockSpotBalance);
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            encodedSpotBalance
        );

        uint256 balance = genesisVaultManager.spotAccountBalance();
        // 3e8 * 1e10 = 3e18
        assertEq(balance, 3e18);
    }

    function test_TotalBalance() public {
        // Mock delegator summary
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 1e8, // 1 HYPE
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        // Mock spot balance
        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 2e8, hold: 0, entryNtl: 0}); // 2 HYPE
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // Add some balance to the staking vault contract itself
        vm.deal(address(stakingVault), 1e18); // 1 HYPE

        uint256 totalBalance = genesisVaultManager.totalBalance();
        // 1e18 (staking) + 2e18 (spot) + 1e18 (contract balance) = 4e18
        assertEq(totalBalance, 4e18);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Exchange Rate                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ExchangeRate_AboveOne() public {
        // Mock total balance to be 4e18
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 2e8, // 2 HYPE
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 2e8, hold: 0, entryNtl: 0}); // 2 HYPE
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // Mint 2 vHYPE tokens
        vm.prank(address(genesisVaultManager));
        vHYPE.mint(user, 2e18);

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        // 4e18 (total balance) / 2e18 (total supply) = 2
        assertEq(exchangeRate, 2e18);
    }

    function test_ExchangeRate_BelowOne() public {
        // Mock total balance to be 4e18
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 2e8, // 2 HYPE
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 2e8, hold: 0, entryNtl: 0}); // 2 HYPE
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // Mint 8 vHYPE tokens
        vm.prank(address(genesisVaultManager));
        vHYPE.mint(user, 8e18);

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        // 4e18 (total balance) / 8e18 (total supply) = 0.5
        assertEq(exchangeRate, 0.5e18);
    }

    function test_ExchangeRate_ZeroBalance() public {
        // Mock total balance to be zero
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 0,
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 0, hold: 0, entryNtl: 0});
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // Mint some vHYPE tokens
        vm.prank(address(genesisVaultManager));
        vHYPE.mint(user, 2e18); // 2 vHYPE tokens

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        assertEq(exchangeRate, 0);
    }

    function test_ExchangeRate_ZeroTotalSupply() public {
        // Mock total balance to be non-zero
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 2e8, // 2 HYPE
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 2e8, hold: 0, entryNtl: 0}); // 2 HYPE
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // No vHYPE tokens minted, so total supply is 0

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        assertEq(exchangeRate, 1e18);
    }

    function test_ExchangeRate_BalanceMoreThanSupply(uint256 totalBalance, uint256 vHYPESupply) public {
        vm.assume(totalBalance >= 1e10); // Minimum to survive division by 1e10
        vm.assume(vHYPESupply > 0);
        vm.assume(totalBalance > vHYPESupply);
        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        assertGt(exchangeRate, 1e18); // exchange rate >= 1
    }

    function test_ExchangeRate_BalanceLessThanSupply(uint256 totalBalance, uint256 vHYPESupply) public {
        vm.assume(totalBalance > 0);
        vm.assume(vHYPESupply > 0);
        vm.assume(totalBalance < vHYPESupply);
        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        assertLt(exchangeRate, 1e18); // exchange rate <= 1
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: HYPETovHYPE and vHYPEtoHYPE Functions       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_HYPETovHYPE_ExchangeRateAboveOne() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(genesisVaultManager.HYPETovHYPE(2e18), 1e18);
    }

    function test_HYPETovHYPE_ExchangeRateBelowOne() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 4e18 /* 4 vHYPE */ ); // exchange rate = 0.5
        assertEq(genesisVaultManager.HYPETovHYPE(2e18), 4e18);
    }

    function test_HYPETovHYPE_ZeroAmount() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(genesisVaultManager.HYPETovHYPE(0), 0);
    }

    function test_HYPETovHYPE_ZeroExchangeRate_ZeroBalance() public {
        _mockBalancesForExchangeRate(0, /* 0 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 0
        assertEq(genesisVaultManager.HYPETovHYPE(1e18), 0);
    }

    function test_HYPETovHYPE_OneExchangeRate_ZeroSupply() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 0 /* 0 vHYPE */ ); // exchange rate = 1
        assertEq(genesisVaultManager.HYPETovHYPE(2e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateAboveOne() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(genesisVaultManager.vHYPEtoHYPE(1e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateBelowOne() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 4e18 /* 4 vHYPE */ ); // exchange rate = 0.5
        assertEq(genesisVaultManager.vHYPEtoHYPE(1e18), 0.5e18);
    }

    function test_vHYPEtoHYPE_ZeroAmount() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(genesisVaultManager.vHYPEtoHYPE(0), 0);
    }

    function test_vHYPEtoHYPE_ZeroExchangeRate_ZeroBalance() public {
        _mockBalancesForExchangeRate(0, /* 0 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 0
        assertEq(genesisVaultManager.vHYPEtoHYPE(1e18), 0);
    }

    function test_vHYPEtoHYPE_ZeroExchangeRate_ZeroSupply() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 0 /* 0 vHYPE */ ); // exchange rate = 1
        assertEq(genesisVaultManager.vHYPEtoHYPE(1e18), 1e18);
    }

    function test_HYPETovHYPE_vHYPEtoHYPE_Roundtrip(
        uint256 totalBalance,
        uint256 vHYPESupply,
        uint256 hypeAmountToConvert
    ) public {
        vm.assume(hypeAmountToConvert > 0 && hypeAmountToConvert < 2_000_000 * 1e18);

        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        // Here we bound the exchange rate to be between 0 and 1e15. Otherwise, we'll see large precision loss
        // with extremely high exchange rates.
        //
        // Extremely high exchange rates are very unlikely to occur in practice. 1e15 is a very geneerous upper
        // bound for the exchange rate (it's 1 million * 1 million, which would only occur if we've earned
        // 1 million HYPE for every vHYPE minted).
        uint256 exchangeRate = genesisVaultManager.exchangeRate();
        vm.assume(exchangeRate > 0 && exchangeRate < 1e15);

        uint256 vHYPEAmount = genesisVaultManager.HYPETovHYPE(hypeAmountToConvert);
        uint256 convertedBackHYPE = genesisVaultManager.vHYPEtoHYPE(vHYPEAmount);

        // Allow for 1-2 wei difference due to rounding
        assertApproxEqAbs(convertedBackHYPE, hypeAmountToConvert, 2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Vault Capacity                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetVaultCapacity_OnlyOwner() public {
        uint256 newCapacity = 1_500_000 * 1e18;

        vm.prank(owner);
        genesisVaultManager.setVaultCapacity(newCapacity);

        assertEq(genesisVaultManager.vaultCapacity(), newCapacity);
    }

    function test_SetVaultCapacity_NotOwner() public {
        uint256 newCapacity = 1_500_000 * 1e18;

        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.setVaultCapacity(newCapacity);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Default Validator                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetDefaultValidator_OnlyOwner() public {
        address newValidator = makeAddr("newValidator");

        vm.prank(owner);
        genesisVaultManager.setDefaultValidator(newValidator);

        assertEq(genesisVaultManager.defaultValidator(), newValidator);
    }

    function test_SetDefaultValidator_NotOwner() public {
        address newValidator = makeAddr("newValidator");

        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.setDefaultValidator(newValidator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Emergency Withdraw                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_EmergencyStakingWithdraw_OnlyOwner() public {
        uint64 withdrawWeiAmount = 100_000 * 1e8; // 100k HYPE (in 8 decimals)
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        _mockDelegatorSummary(withdrawWeiAmount);
        _mockAndExpectStakingWithdrawCall(withdrawWeiAmount);
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), withdrawWeiAmount, true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyStakingWithdraw(owner, withdrawAmount, "Emergency staking withdraw");
        genesisVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.emergencyStakingWithdraw(1_000_000 * 1e18, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_InsufficientBalance() public {
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        _mockDelegatorSummary(50_000 * 1e8); // 50k HYPE delegated (in 8 decimals)

        vm.prank(owner);
        vm.expectRevert("Insufficient delegated balance");
        genesisVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_ZeroAmount() public {
        _mockDelegatorSummary(uint64(1_000_000 * 1e8)); // 1M HYPE delegated

        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        genesisVaultManager.emergencyStakingWithdraw(0, "Emergency staking withdraw");
    }

    function test_ProtocolWithdraw_EmptyPurposeString() public {
        _mockDelegatorSummary(uint64(1_000_000 * 1e8)); // 1M HYPE delegated

        vm.prank(owner);
        vm.expectRevert("Purpose must be set");
        genesisVaultManager.emergencyStakingWithdraw(1_000_000 * 1e18, "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Upgradeability                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        GenesisVaultManagerWithExtraFunction newImplementation = new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.prank(owner);
        genesisVaultManager.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(genesisVaultManager.protocolRegistry()), address(protocolRegistry));
        assertEq(genesisVaultManager.vaultCapacity(), VAULT_CAPACITY);

        // Check that the extra function is available
        GenesisVaultManagerWithExtraFunction newProxy =
            GenesisVaultManagerWithExtraFunction(payable(address(genesisVaultManager)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner() public {
        GenesisVaultManagerWithExtraFunction newImplementation = new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.upgradeToAndCall(address(newImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Receive and Fallback Functions         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Receive() public {
        uint256 amount = 1e18;
        uint256 balanceBefore = address(genesisVaultManager).balance;

        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(genesisVaultManager).call{value: amount}("");

        assertTrue(success);
        assertEq(address(genesisVaultManager).balance, balanceBefore + amount);
    }

    function test_Fallback() public {
        uint256 amount = 1e18;
        uint256 balanceBefore = address(genesisVaultManager).balance;

        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(genesisVaultManager).call{value: amount}("0x1234");

        assertTrue(success);
        assertEq(address(genesisVaultManager).balance, balanceBefore + amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Helper Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to mock balances for testing exchange rate calculations
    /// @param totalBalance The total balance of HYPE to mock (in 18 decimals)
    /// @param vHYPESupply The total supply of vHYPE to mint (in 18 decimals)
    function _mockBalancesForExchangeRate(uint256 totalBalance, uint256 vHYPESupply) internal {
        vm.assume(totalBalance / 1e10 <= type(uint64).max);

        uint64 delegatedBalance = totalBalance > 0 ? uint64(totalBalance / 1e10) : 0; // Convert to 8 decimals

        // Mock delegator summary and spot balance
        _mockDelegatorSummary(delegatedBalance);
        _mockSpotBalance(0); // Zero for simplicity

        // Mint the desired total supply to owner
        if (vHYPESupply > 0) {
            vm.prank(address(genesisVaultManager));
            vHYPE.mint(owner, vHYPESupply);
        }
    }

    /// @dev Helper function to mock delegator summary for testing staking deposit calls
    /// @param delegated The delegated balance to mock (in 8 decimals)
    function _mockDelegatorSummary(uint64 delegated) internal {
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(
                L1ReadLibrary.DelegatorSummary({
                    delegated: delegated,
                    undelegated: 0,
                    totalPendingWithdrawal: 0,
                    nPendingWithdrawals: 0
                })
            )
        );
    }

    /// @dev Helper function to mock spot balance for testing staking deposit calls
    /// @param total The total balance to mock (in 8 decimals)
    function _mockSpotBalance(uint64 total) internal {
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(L1ReadLibrary.SpotBalance({total: total, hold: 0, entryNtl: 0}))
        );
    }

    function _mockAndExpectStakingDepositCall(uint64 weiAmount) internal {
        bytes memory encodedAction = abi.encode(weiAmount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x04; // Staking deposit action ID
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, data),
            abi.encode()
        );
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));
    }

    function _mockAndExpectStakingWithdrawCall(uint64 weiAmount) internal {
        bytes memory encodedAction = abi.encode(weiAmount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x05; // Staking withdraw action ID
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, data),
            abi.encode()
        );
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));
    }

    function _mockAndExpectTokenDelegateCall(address validator, uint64 weiAmount, bool isUndelegate) internal {
        bytes memory encodedAction = abi.encode(validator, weiAmount, isUndelegate);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, data),
            abi.encode()
        );
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));
    }
}

contract GenesisVaultManagerWithExtraFunction is GenesisVaultManager {
    constructor(uint64 _hypeTokenId) GenesisVaultManager(_hypeTokenId) {}

    function extraFunction() public pure returns (bool) {
        return true;
    }
}

contract StakingVaultThatRejectsTransfers is StakingVault {
    // Reject all incoming transfers
    receive() external payable override {
        revert("Staking vault transfer rejected");
    }

    fallback() external payable override {
        revert("Staking vault transfer rejected");
    }
}

contract ContractThatRejectsTransfers {
    // Reject all incoming transfers
    receive() external payable {
        revert("Transfer rejected");
    }

    fallback() external payable {
        revert("Transfer rejected");
    }
}

contract MockHypeSystemContract {
    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address internal constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    uint64 public constant HYPE_TOKEN_ID = 150;

    receive() external payable {
        uint64 amount = SafeCast.toUint64(msg.value / 1e10);

        // When we receive HYPE, we want to add it to the spot balance to simulate a "transfer" to the address's
        // spot account
        L1ReadLibrary.SpotBalance memory spotBalance = L1ReadLibrary.spotBalance(msg.sender, HYPE_TOKEN_ID);
        L1ReadLibrary.SpotBalance memory newSpotBalance = L1ReadLibrary.SpotBalance({
            total: spotBalance.total + amount,
            hold: spotBalance.hold,
            entryNtl: spotBalance.entryNtl
        });
        Vm(VM_ADDRESS).mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(msg.sender, HYPE_TOKEN_ID),
            abi.encode(newSpotBalance)
        );
    }
}
