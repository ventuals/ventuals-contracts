// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract GenesisVaultManagerTest is Test {
    GenesisVaultManager genesisVaultManager;
    ProtocolRegistry protocolRegistry;
    VHYPE vHYPE;
    StakingVault stakingVault;

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");

    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID
    uint256 public constant VAULT_CAPACITY = 1000e18; // 1000 HYPE
    uint256 public constant EVM_RESERVE = 100e18; // 100 HYPE

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
            EVM_RESERVE
        );
        ERC1967Proxy genesisVaultManagerProxy =
            new ERC1967Proxy(address(genesisVaultManagerImplementation), genesisVaultManagerInitData);
        genesisVaultManager = GenesisVaultManager(payable(genesisVaultManagerProxy));

        // Setup roles
        vm.startPrank(owner);
        protocolRegistry.grantRole(protocolRegistry.MANAGER_ROLE(), manager);
        protocolRegistry.grantRole(protocolRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Initialization                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public {
        assertEq(address(genesisVaultManager.protocolRegistry()), address(protocolRegistry));
        assertEq(address(genesisVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(genesisVaultManager.stakingVault()), address(stakingVault));
        assertEq(genesisVaultManager.vaultCapacity(), VAULT_CAPACITY);
        assertEq(genesisVaultManager.evmReserve(), EVM_RESERVE);
        assertEq(genesisVaultManager.HYPE_TOKEN_ID(), HYPE_TOKEN_ID);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert("InvalidInitialization()");
        genesisVaultManager.initialize(
            address(protocolRegistry), address(vHYPE), address(stakingVault), VAULT_CAPACITY, EVM_RESERVE
        );
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
        vm.prank(manager);
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
        vm.prank(manager);
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
        vm.prank(manager);
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
    /*             Tests: Vault Capacity and EVM Reserve          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetVaultCapacity_OnlyOwner() public {
        uint256 newCapacity = 2000e18;

        vm.prank(owner);
        genesisVaultManager.setVaultCapacity(newCapacity);

        assertEq(genesisVaultManager.vaultCapacity(), newCapacity);
    }

    function test_SetVaultCapacity_NotOwner() public {
        uint256 newCapacity = 2000e18;

        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.setVaultCapacity(newCapacity);
    }

    function test_SetVaultCapacity_MustBeGreaterThanEvmReserve() public {
        uint256 invalidCapacity = 50e18; // Less than EVM_RESERVE (100e18)

        vm.prank(owner);
        vm.expectRevert("Vault capacity must be greater than EVM reserve");
        genesisVaultManager.setVaultCapacity(invalidCapacity);
    }

    function test_SetEvmReserve_OnlyOwner() public {
        uint256 newReserve = 200e18;

        vm.prank(owner);
        genesisVaultManager.setEvmReserve(newReserve);

        assertEq(genesisVaultManager.evmReserve(), newReserve);
    }

    function test_SetEvmReserve_NotOwner() public {
        uint256 newReserve = 200e18;

        vm.prank(user);
        vm.expectRevert("Caller is not the owner");
        genesisVaultManager.setEvmReserve(newReserve);
    }

    function test_SetEvmReserve_MustBeLessThanVaultCapacity() public {
        uint256 invalidReserve = 1500e18; // Greater than VAULT_CAPACITY (1000e18)

        vm.prank(owner);
        vm.expectRevert("EVM reserve must be less than vault capacity");
        genesisVaultManager.setEvmReserve(invalidReserve);
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
        assertEq(genesisVaultManager.evmReserve(), EVM_RESERVE);

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

        // Mock delegator summary and spot balance to achieve the desired total balance
        uint64 delegatedBalance = totalBalance > 0 ? uint64(totalBalance / 1e10) : 0; // Convert to 8 decimals

        // Mock delegator summary
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: delegatedBalance,
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault)),
            abi.encode(mockDelegatorSummary)
        );

        // Mock spot balance; zero for simplicity
        L1ReadLibrary.SpotBalance memory mockSpotBalance = L1ReadLibrary.SpotBalance({total: 0, hold: 0, entryNtl: 0});
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(mockSpotBalance)
        );

        // Mint the desired total supply to owner
        if (vHYPESupply > 0) {
            vm.prank(manager);
            vHYPE.mint(owner, vHYPESupply);
        }
    }
}

contract GenesisVaultManagerWithExtraFunction is GenesisVaultManager {
    constructor(uint64 _hypeTokenId) GenesisVaultManager(_hypeTokenId) {}

    function extraFunction() public pure returns (bool) {
        return true;
    }
}
