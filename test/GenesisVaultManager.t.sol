// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {IStakingVault} from "../src/interfaces/IStakingVault.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Vm} from "forge-std/Vm.sol";
import {Base} from "../src/Base.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract GenesisVaultManagerTest is Test {
    GenesisVaultManager genesisVaultManager;
    RoleRegistry roleRegistry;
    VHYPE vHYPE;
    StakingVault stakingVault;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");

    address public defaultValidator = makeAddr("defaultValidator");
    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID
    uint256 public constant VAULT_CAPACITY = 1_200_000 * 1e18; // 1.2M HYPE
    uint256 public constant DEFAULT_DEPOSIT_LIMIT = 100_000 * 1e18; // 100k HYPE
    uint256 public constant MINIMUM_DEPOSIT_AMOUNT = 1e16; // 0.01 HYPE

    // Events
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);

    function setUp() public {
        // Deploy RoleRegistry
        RoleRegistry roleRegistryImplementation = new RoleRegistry();
        bytes memory roleRegistryInitData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);
        ERC1967Proxy roleRegistryProxy = new ERC1967Proxy(address(roleRegistryImplementation), roleRegistryInitData);
        roleRegistry = RoleRegistry(address(roleRegistryProxy));

        // Deploy vHYPE token
        VHYPE vhypeImplementation = new VHYPE();
        bytes memory vhypeInitData = abi.encodeWithSelector(vHYPE.initialize.selector, address(roleRegistry));
        ERC1967Proxy vhypeProxy = new ERC1967Proxy(address(vhypeImplementation), vhypeInitData);
        vHYPE = VHYPE(address(vhypeProxy));

        // Deploy StakingVault
        StakingVault stakingVaultImplementation = new StakingVault();
        bytes memory stakingVaultInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(roleRegistry));
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        stakingVault = StakingVault(payable(stakingVaultProxy));

        // Deploy GenesisVaultManager
        GenesisVaultManager genesisVaultManagerImplementation = new GenesisVaultManager(HYPE_TOKEN_ID);
        bytes memory genesisVaultManagerInitData = abi.encodeWithSelector(
            GenesisVaultManager.initialize.selector,
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            VAULT_CAPACITY,
            defaultValidator,
            DEFAULT_DEPOSIT_LIMIT,
            MINIMUM_DEPOSIT_AMOUNT
        );
        ERC1967Proxy genesisVaultManagerProxy =
            new ERC1967Proxy(address(genesisVaultManagerImplementation), genesisVaultManagerInitData);
        genesisVaultManager = GenesisVaultManager(payable(genesisVaultManagerProxy));

        // Setup roles
        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), address(genesisVaultManager));
        roleRegistry.grantRole(roleRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock HYPE system contract
        MockHypeSystemContract mockHypeSystemContract = new MockHypeSystemContract();
        vm.etch(0x2222222222222222222222222222222222222222, address(mockHypeSystemContract).code);
        _mockSpotBalance(0);
        _mockDelegatorSummary(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Initialization                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public view {
        assertEq(address(genesisVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(address(genesisVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(genesisVaultManager.stakingVault()), address(stakingVault));
        assertEq(genesisVaultManager.vaultCapacity(), VAULT_CAPACITY);
        assertEq(genesisVaultManager.defaultValidator(), defaultValidator);
        assertEq(genesisVaultManager.defaultDepositLimit(), DEFAULT_DEPOSIT_LIMIT);
        assertEq(genesisVaultManager.minimumDepositAmount(), MINIMUM_DEPOSIT_AMOUNT);
        assertEq(genesisVaultManager.HYPE_TOKEN_ID(), HYPE_TOKEN_ID);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        genesisVaultManager.initialize(
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            VAULT_CAPACITY,
            defaultValidator,
            DEFAULT_DEPOSIT_LIMIT,
            MINIMUM_DEPOSIT_AMOUNT
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Tests: Deposit Function               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Deposit_FullDepositIntoEmptyVault() public {
        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that we minted 1:1 vHYPE when vault is empty
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);

        assertEq(userVHYPEBalance, depositAmount);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_FullDepositIntoVaultWithExistingBalance() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k HYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // 1:1 ratio

        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_PartialDepositIntoVaultWithExistingBalance() public {
        uint256 existingBalance = 1_150_000 * 1e18; // 1.15M HYPE
        uint256 existingSupply = 1_150_000 * 1e18; // 1.15M vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // 1:1 ratio

        // Attempt to deposit 100k HYPE; only 50k HYPE will be accepted
        uint256 depositAmount = 100_000 * 1e18;

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 50_000 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 50_000 * 1e18); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, 50_000 * 1e18);

        // Check user was refunded the excess
        assertEq(user.balance, 50_000 * 1e18);
    }

    function test_Deposit_ExchangeRateAboveOneFullDeposit() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 250_000 * 1e18; // 250k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 2

        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount / 2);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateAboveOnePartialDeposit() public {
        uint256 existingBalance = 1_150_000 * 1e18; // 1.15M HYPE
        uint256 existingSupply = 575_000 * 1e18; // 575k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 2

        // Attempt to deposit 100k HYPE; only 50k HYPE will be accepted
        uint256 depositAmount = 100_000 * 1e18;

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 25_000 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 50_000 * 1e18); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, 50_000 * 1e18);

        // Check user was refunded the excess
        assertEq(user.balance, 50_000 * 1e18);
    }

    function test_Deposit_ExchangeRateBelowOneFullDeposit() public {
        uint256 existingBalance = 250_000 * 1e18; // 250k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 0.5

        uint256 depositAmount = 100_000 * 1e18; // 100k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount * 2);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateBelowOnePartialDeposit() public {
        uint256 existingBalance = 1_150_000 * 1e18; // 1.15M HYPE
        uint256 existingSupply = 2_300_000 * 1e18; // 2.3M vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 0.5

        // Attempt to deposit 100k HYPE; only 50k HYPE will be accepted
        uint256 depositAmount = 100_000 * 1e18;

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, 50_000 * 2 * 1e18);
        assertEq(genesisVaultManager.vHYPEtoHYPE(userVHYPEBalance), 50_000 * 1e18); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, 50_000 * 1e18);

        // Check user was refunded the excess
        assertEq(user.balance, 50_000 * 1e18);
    }

    function test_Deposit_RevertWhenVaultFull(uint256 depositAmount) public {
        vm.assume(depositAmount >= 1e16);
        _mockBalancesForExchangeRate(VAULT_CAPACITY, VAULT_CAPACITY);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vm.expectRevert(GenesisVaultManager.VaultFull.selector);
        genesisVaultManager.deposit{value: depositAmount}();

        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(address(stakingVault).balance, 0);
    }

    function test_Deposit_ExactMinimumAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        vm.deal(user, MINIMUM_DEPOSIT_AMOUNT);
        vm.prank(user);
        genesisVaultManager.deposit{value: MINIMUM_DEPOSIT_AMOUNT}();

        // vHYPE should be minted
        assertEq(vHYPE.balanceOf(user), MINIMUM_DEPOSIT_AMOUNT);

        // HYPE should be transferred to staking vault
        assertEq(address(stakingVault).balance, MINIMUM_DEPOSIT_AMOUNT);
    }

    function test_Deposit_BelowMinimumAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        uint256 belowMinimumAmount = MINIMUM_DEPOSIT_AMOUNT - 1; // 1 wei below minimum

        vm.deal(user, belowMinimumAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(GenesisVaultManager.BelowMinimumDepositAmount.selector));
        genesisVaultManager.deposit{value: belowMinimumAmount}();
    }

    function test_Deposit_ZeroAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(GenesisVaultManager.BelowMinimumDepositAmount.selector));
        genesisVaultManager.deposit{value: 0}();
    }

    function test_Deposit_RevertWhenContractPaused() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(genesisVaultManager));

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(genesisVaultManager)));
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that no HYPE was transferred to staking vault (vault balance should remain 0)
        assertEq(address(stakingVault).balance, 0);

        // Check that no vHYPE was minted
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

        uint256 depositAmount = 100_000 * 1e18; // 100k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(GenesisVaultManager.TransferFailed.selector, address(stakingVault), depositAmount)
        );
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that no vHYPE was minted
        assertEq(vHYPE.balanceOf(user), 0);

        // Check that no HYPE was transferred to staking vault (vault balance should remain 0)
        assertEq(address(stakingVault).balance, 0);
    }

    function test_Deposit_RevertWhenRefundFails() public {
        uint256 existingBalance = 1_150_000 * 1e18; // 1.15M HYPE
        uint256 existingSupply = 1_150_000 * 1e18; // 1.15M vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        // Attempt to deposit 100k HYPE; only 50k HYPE will be accepted
        uint256 depositAmount = 100_000 * 1e18; // 100k HYPE

        // Create a contract that rejects refunds
        ContractThatRejectsTransfers contractThatRejectsTransfers = new ContractThatRejectsTransfers();

        vm.deal(address(contractThatRejectsTransfers), depositAmount);
        vm.startPrank(address(contractThatRejectsTransfers));
        vm.expectRevert(
            abi.encodeWithSelector(
                GenesisVaultManager.TransferFailed.selector,
                address(contractThatRejectsTransfers),
                depositAmount - (VAULT_CAPACITY - existingBalance)
            )
        );
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that no vHYPE was minted
        assertEq(vHYPE.balanceOf(address(contractThatRejectsTransfers)), 0);

        // Check that no HYPE was transferred to staking vault (vault balance should remain 0)
        assertEq(address(stakingVault).balance, 0);
    }

    function test_Deposit_RevertWhenDepositLimitReached() public {
        // First deposit up to the limit
        vm.deal(user, DEFAULT_DEPOSIT_LIMIT);

        vm.prank(user);
        genesisVaultManager.deposit{value: DEFAULT_DEPOSIT_LIMIT}();

        // Second deposit should revert
        uint256 additionalDeposit = 1 * 1e18; // 1 HYPE
        vm.deal(user, additionalDeposit);
        vm.startPrank(user);
        vm.expectRevert(GenesisVaultManager.DepositLimitReached.selector);
        genesisVaultManager.deposit{value: additionalDeposit}();
    }

    function test_Deposit_SuccessWithWhitelistedLimit() public {
        address whitelistedUser = makeAddr("whitelistedUser");
        uint256 whitelistLimit = 500_000 * 1e18; // 500k HYPE
        uint256 depositAmount = 200_000 * 1e18; // 200k HYPE

        // Whitelist the user with higher limit
        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, whitelistLimit);

        vm.deal(whitelistedUser, depositAmount);
        vm.prank(whitelistedUser);
        genesisVaultManager.deposit{value: depositAmount}();

        // Check that vHYPE was minted
        assertEq(vHYPE.balanceOf(whitelistedUser), depositAmount);
        assertEq(whitelistedUser.balance, 0);

        // Check that HYPE was transferred to staking vault
        assertEq(address(stakingVault).balance, depositAmount);
    }

    function test_Deposit_RevertWhenWhitelistedLimitReached() public {
        address whitelistedUser = makeAddr("whitelistedUser");
        uint256 whitelistLimit = 50_000 * 1e18; // 50k HYPE (lower than default)

        // Whitelist the user with lower limit
        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, whitelistLimit);

        // First deposit up to the whitelist limit

        vm.deal(whitelistedUser, whitelistLimit);
        vm.prank(whitelistedUser);
        genesisVaultManager.deposit{value: whitelistLimit}();

        // Second deposit should revert
        uint256 additionalDeposit = 1 * 1e18; // 1 HYPE
        vm.deal(whitelistedUser, additionalDeposit);
        vm.startPrank(whitelistedUser);
        vm.expectRevert(GenesisVaultManager.DepositLimitReached.selector);
        genesisVaultManager.deposit{value: additionalDeposit}();
    }

    function test_Deposit_PartialDepositDueToDepositLimit() public {
        // Try to deposit more than the limit
        uint256 requestedAmount = DEFAULT_DEPOSIT_LIMIT + 50_000 * 1e18; // 150k HYPE
        uint256 expectedDepositAmount = DEFAULT_DEPOSIT_LIMIT; // Only 100k HYPE should be deposited

        // Mock staking vault calls for the limited amount

        vm.deal(user, requestedAmount);
        vm.prank(user);
        genesisVaultManager.deposit{value: requestedAmount}();

        // Check that only the limit was deposited and rest was refunded
        assertEq(vHYPE.balanceOf(user), expectedDepositAmount);
        assertEq(user.balance, requestedAmount - expectedDepositAmount);

        // Check that only the accepted amount was transferred to staking vault
        assertEq(address(stakingVault).balance, expectedDepositAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Remaining Deposit Limits               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_RemainingDepositLimit_NoDeposits() public view {
        uint256 remaining = genesisVaultManager.remainingDepositLimit(user);
        assertEq(remaining, DEFAULT_DEPOSIT_LIMIT);
    }

    function test_RemainingDepositLimit_WithDeposits() public {
        // Mock a deposit of 30k HYPE for the user
        uint256 depositAmount = 30_000 * 1e18;

        vm.deal(user, depositAmount);
        vm.prank(user);
        genesisVaultManager.deposit{value: depositAmount}();

        uint256 remaining = genesisVaultManager.remainingDepositLimit(user);
        assertEq(remaining, DEFAULT_DEPOSIT_LIMIT - depositAmount);

        // Check that HYPE was transferred to staking vault
        assertEq(address(stakingVault).balance, depositAmount);
    }

    function test_RemainingDepositLimit_MaxDeposits() public {
        vm.deal(user, DEFAULT_DEPOSIT_LIMIT);
        vm.prank(user);
        genesisVaultManager.deposit{value: DEFAULT_DEPOSIT_LIMIT}();

        uint256 remaining = genesisVaultManager.remainingDepositLimit(user);
        assertEq(remaining, 0);

        // Check that HYPE was transferred to staking vault
        assertEq(address(stakingVault).balance, DEFAULT_DEPOSIT_LIMIT);
    }

    function test_RemainingDepositLimit_WithWhitelistHigherLimit() public {
        address whitelistedUser = makeAddr("whitelistedUser");
        uint256 whitelistLimit = 500_000 * 1e18; // 500k HYPE

        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, whitelistLimit);

        uint256 remaining = genesisVaultManager.remainingDepositLimit(whitelistedUser);
        assertEq(remaining, whitelistLimit);
    }

    function test_RemainingDepositLimit_WithWhitelistLowerLimit() public {
        address whitelistedUser = makeAddr("whitelistedUser");
        uint256 whitelistLimit = 50_000 * 1e18; // 50k HYPE

        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, whitelistLimit);

        uint256 remaining = genesisVaultManager.remainingDepositLimit(whitelistedUser);
        assertEq(remaining, whitelistLimit);
    }

    function test_RemainingDepositLimit_WhitelistZeroLimit() public {
        address whitelistedUser = makeAddr("whitelistedUser");

        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, 0);

        // When whitelist is 0, should use default limit
        uint256 remaining = genesisVaultManager.remainingDepositLimit(whitelistedUser);
        assertEq(remaining, DEFAULT_DEPOSIT_LIMIT);
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
    /*              Tests: Vault Capacity (Only Owner)            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetVaultCapacity_OnlyOwner() public {
        uint256 newCapacity = 1_500_000 * 1e18;

        vm.prank(owner);
        genesisVaultManager.setVaultCapacity(newCapacity);

        assertEq(genesisVaultManager.vaultCapacity(), newCapacity);
    }

    function test_SetVaultCapacity_NotOwner() public {
        uint256 newCapacity = 1_500_000 * 1e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.setVaultCapacity(newCapacity);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*            Tests: Set Default Validator (Only Owner)       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetDefaultValidator_OnlyOwner() public {
        address newValidator = makeAddr("newValidator");

        vm.prank(owner);
        genesisVaultManager.setDefaultValidator(newValidator);

        assertEq(genesisVaultManager.defaultValidator(), newValidator);
    }

    function test_SetDefaultValidator_NotOwner() public {
        address newValidator = makeAddr("newValidator");

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.setDefaultValidator(newValidator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       Tests: Set Minimum Deposit Amount (Only Owner)      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMinimumDepositAmount_OnlyOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.prank(owner);
        genesisVaultManager.setMinimumDepositAmount(newMinimumAmount);

        assertEq(genesisVaultManager.minimumDepositAmount(), newMinimumAmount);
    }

    function test_SetMinimumDepositAmount_NotOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.setMinimumDepositAmount(newMinimumAmount);
    }

    function test_SetMinimumDepositAmount_UpdatesDepositValidation() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE
        uint256 belowNewMinimum = newMinimumAmount - 1; // 1 wei below new minimum

        // Set new minimum amount
        vm.prank(owner);
        genesisVaultManager.setMinimumDepositAmount(newMinimumAmount);

        // Mock balances for deposit
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply);

        // Try to deposit below new minimum - should fail
        vm.deal(user, belowNewMinimum);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(GenesisVaultManager.BelowMinimumDepositAmount.selector));
        genesisVaultManager.deposit{value: belowNewMinimum}();

        // Deposit exactly the new minimum - should succeed
        vm.deal(user, newMinimumAmount);
        genesisVaultManager.deposit{value: newMinimumAmount}();

        // Verify deposit succeeded
        assertEq(vHYPE.balanceOf(user), newMinimumAmount);
        assertEq(address(stakingVault).balance, newMinimumAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          Tests: Redelegate Stake (Only Owner)              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RedelegateStake(address indexed fromValidator, address indexed toValidator, uint256 amount);

    function test_RedelegateStake_OnlyOwner() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint256 amount = 100_000 * 1e18; // 100k HYPE

        // Mock the undelegate call (from validator)
        _mockAndExpectTokenDelegateCall(fromValidator, uint64(amount / 1e10), true);
        // Mock the delegate call (to validator)
        _mockAndExpectTokenDelegateCall(toValidator, uint64(amount / 1e10), false);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit RedelegateStake(fromValidator, toValidator, amount);
        genesisVaultManager.redelegateStake(fromValidator, toValidator, amount);
    }

    function test_RedelegateStake_NotOwner() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint256 amount = 100_000 * 1e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.redelegateStake(fromValidator, toValidator, amount);
    }

    function test_RedelegateStake_ZeroAmount() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");

        vm.startPrank(owner);
        vm.expectRevert(GenesisVaultManager.ZeroAmount.selector);
        genesisVaultManager.redelegateStake(fromValidator, toValidator, 0);
    }

    function test_RedelegateStake_SameValidator() public {
        address validator = makeAddr("validator");
        uint256 amount = 100_000 * 1e18; // 100k HYPE

        vm.startPrank(owner);
        vm.expectRevert(GenesisVaultManager.RedelegateToSameValidator.selector);
        genesisVaultManager.redelegateStake(validator, validator, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       Tests: Set Default Deposit Limit (Only Owner)        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetDefaultDepositLimit_OnlyOwner() public {
        uint256 newLimit = 200_000 * 1e18; // 200k HYPE

        vm.prank(owner);
        genesisVaultManager.setDefaultDepositLimit(newLimit);

        assertEq(genesisVaultManager.defaultDepositLimit(), newLimit);
    }

    function test_SetDefaultDepositLimit_NotOwner() public {
        uint256 newLimit = 200_000 * 1e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.setDefaultDepositLimit(newLimit);
    }

    function test_SetDefaultDepositLimit_ZeroLimit() public {
        vm.prank(owner);
        genesisVaultManager.setDefaultDepositLimit(0);

        assertEq(genesisVaultManager.defaultDepositLimit(), 0);
    }

    function test_SetDefaultDepositLimit_LowerThanDepositedAmount() public {
        // Max out the default deposit limit
        vm.deal(user, DEFAULT_DEPOSIT_LIMIT);
        vm.prank(user);
        genesisVaultManager.deposit{value: DEFAULT_DEPOSIT_LIMIT}();

        // Set default deposit limit lower than deposited amount
        vm.prank(owner);
        genesisVaultManager.setDefaultDepositLimit(DEFAULT_DEPOSIT_LIMIT / 2);

        // Check that remaining deposit limit is 0
        assertEq(genesisVaultManager.remainingDepositLimit(user), 0);

        // Check that HYPE was transferred to staking vault
        assertEq(address(stakingVault).balance, DEFAULT_DEPOSIT_LIMIT);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: Whitelist Deposit Limit (Only Owner)        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetWhitelistDepositLimit_OnlyOwner() public {
        address userToWhitelist = makeAddr("userToWhitelist");
        uint256 whitelistLimit = 500_000 * 1e18; // 500k HYPE

        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(userToWhitelist, whitelistLimit);

        uint256 remaining = genesisVaultManager.remainingDepositLimit(userToWhitelist);
        assertEq(remaining, whitelistLimit);
    }

    function test_SetWhitelistDepositLimit_NotOwner() public {
        address userToWhitelist = makeAddr("userToWhitelist");
        uint256 whitelistLimit = 500_000 * 1e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.setWhitelistDepositLimit(userToWhitelist, whitelistLimit);
    }

    function test_SetWhitelistDepositLimit_ZeroReturnsToDefault() public {
        address userToWhitelist = makeAddr("userToWhitelist");

        vm.startPrank(owner);
        // First set a custom limit
        genesisVaultManager.setWhitelistDepositLimit(userToWhitelist, 500_000 * 1e18);
        // Then reset to 0 (should use default)
        genesisVaultManager.setWhitelistDepositLimit(userToWhitelist, 0);
        vm.stopPrank();

        uint256 remaining = genesisVaultManager.remainingDepositLimit(userToWhitelist);
        assertEq(remaining, DEFAULT_DEPOSIT_LIMIT);
    }

    function test_SetWhitelistDepositLimit_MultipleUsers() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 limit1 = 300_000 * 1e18;
        uint256 limit2 = 750_000 * 1e18;

        vm.startPrank(owner);
        genesisVaultManager.setWhitelistDepositLimit(user1, limit1);
        genesisVaultManager.setWhitelistDepositLimit(user2, limit2);
        vm.stopPrank();

        assertEq(genesisVaultManager.remainingDepositLimit(user1), limit1);
        assertEq(genesisVaultManager.remainingDepositLimit(user2), limit2);
        // Regular user should still have default limit
        assertEq(genesisVaultManager.remainingDepositLimit(user), DEFAULT_DEPOSIT_LIMIT);
    }

    function test_SetWhitelistDepositLimit_LowerThanDepositedAmount() public {
        address whitelistedUser = makeAddr("whitelistedUser");
        uint256 whitelistLimit = 500_000 * 1e18; // 500k HYPE

        // Whitelist the user with higher limit
        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, whitelistLimit);

        // Whitelist user deposits HYPE with higher limit
        vm.deal(whitelistedUser, whitelistLimit);
        vm.prank(whitelistedUser);
        genesisVaultManager.deposit{value: whitelistLimit}();

        // Set whitelist limit lower than deposited amount
        vm.prank(owner);
        genesisVaultManager.setWhitelistDepositLimit(whitelistedUser, 0);

        // Check that remaining deposit limit is 0
        assertEq(genesisVaultManager.remainingDepositLimit(whitelistedUser), 0);

        // Check that HYPE was transferred to staking vault
        assertEq(address(stakingVault).balance, whitelistLimit);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             Tests: Emergency Withdraw (Only Owner)         */
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
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.emergencyStakingWithdraw(1_000_000 * 1e18, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_InsufficientBalance() public {
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        _mockDelegatorSummary(50_000 * 1e8); // 50k HYPE delegated (in 8 decimals)

        vm.startPrank(owner);
        vm.expectRevert(GenesisVaultManager.InsufficientBalance.selector);
        genesisVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_ZeroAmount() public {
        _mockDelegatorSummary(uint64(1_000_000 * 1e8)); // 1M HYPE delegated

        vm.startPrank(owner);
        vm.expectRevert(GenesisVaultManager.ZeroAmount.selector);
        genesisVaultManager.emergencyStakingWithdraw(0, "Emergency staking withdraw");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       Tests: Transfer to Core and Delegate (Only Operator) */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TransferToCoreAndDelegate_AllBalance() public {
        uint256 stakingVaultBalance = 100_000 * 1e18; // 100k HYPE
        vm.deal(address(stakingVault), stakingVaultBalance);

        // Mock the expected calls for transferring all balance
        _mockAndExpectStakingDepositCall(uint64(stakingVaultBalance / 1e10));
        _mockAndExpectTokenDelegateCall(
            genesisVaultManager.defaultValidator(), uint64(stakingVaultBalance / 1e10), false
        );

        vm.prank(operator);
        genesisVaultManager.transferToCoreAndDelegate();

        // Check that lastEvmToCoreTransferBlockNumber was updated
        assertEq(genesisVaultManager.lastEvmToCoreTransferBlockNumber(), block.number);
    }

    function test_TransferToCoreAndDelegate_SpecificAmount() public {
        uint256 stakingVaultBalance = 100_000 * 1e18; // 100k HYPE
        uint256 transferAmount = 50_000 * 1e18; // 50k HYPE
        vm.deal(address(stakingVault), stakingVaultBalance);

        // Mock the expected calls for transferring specific amount
        _mockAndExpectStakingDepositCall(uint64(transferAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(transferAmount / 1e10), false);

        vm.prank(operator);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);

        // Check that lastEvmToCoreTransferBlockNumber was updated
        assertEq(genesisVaultManager.lastEvmToCoreTransferBlockNumber(), block.number);
    }

    function test_TransferToCoreAndDelegate_NotOperator() public {
        uint256 transferAmount = 50_000 * 1e18; // 50k HYPE
        vm.deal(address(stakingVault), transferAmount);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, roleRegistry.OPERATOR_ROLE()
            )
        );
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);
    }

    function test_TransferToCoreAndDelegate_ZeroAmount() public {
        vm.startPrank(operator);
        vm.expectRevert(GenesisVaultManager.ZeroAmount.selector);
        genesisVaultManager.transferToCoreAndDelegate(0);
    }

    function test_TransferToCoreAndDelegate_InsufficientBalance() public {
        uint256 stakingVaultBalance = 50_000 * 1e18; // 50k HYPE
        uint256 transferAmount = 100_000 * 1e18; // 100k HYPE (more than balance)
        vm.deal(address(stakingVault), stakingVaultBalance);

        vm.startPrank(operator);
        vm.expectRevert(GenesisVaultManager.InsufficientBalance.selector);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);
    }

    function test_TransferToCoreAndDelegate_OneBlockDelayRestriction() public {
        uint256 transferAmount = 50_000 * 1e18; // 50k HYPE
        vm.deal(address(stakingVault), transferAmount);

        // First, make a transfer to set lastEvmToCoreTransferBlockNumber
        _mockAndExpectStakingDepositCall(uint64(transferAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(transferAmount / 1e10), false);

        vm.prank(operator);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);

        // Try to make another transfer in the same block - should fail
        vm.deal(address(stakingVault), transferAmount); // Refill balance
        vm.startPrank(operator);
        vm.expectRevert(GenesisVaultManager.CannotTransferToCoreUntilNextBlock.selector);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);
        vm.stopPrank();

        // Advance to next block - should succeed
        _mockAndExpectStakingDepositCall(uint64(transferAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(transferAmount / 1e10), false);

        vm.roll(block.number + 1);
        vm.prank(operator);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);
    }

    function test_TransferToCoreAndDelegate_BlocksDepositInSameBlock() public {
        uint256 transferAmount = 50_000 * 1e18; // 50k HYPE
        uint256 depositAmount = 10_000 * 1e18; // 10k HYPE

        // Set up staking vault balance for transfer
        vm.deal(address(stakingVault), transferAmount);

        // Mock the expected calls for the transfer
        _mockAndExpectStakingDepositCall(uint64(transferAmount / 1e10));
        _mockAndExpectTokenDelegateCall(genesisVaultManager.defaultValidator(), uint64(transferAmount / 1e10), false);

        // Execute the transfer to HyperCore
        vm.prank(operator);
        genesisVaultManager.transferToCoreAndDelegate(transferAmount);

        // Try to make a deposit in the same block - should fail due to one-block delay
        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vm.expectRevert(GenesisVaultManager.CannotDepositUntilNextBlock.selector);
        genesisVaultManager.deposit{value: depositAmount}();
        vm.stopPrank();

        // Advance to next block - deposit should now succeed
        vm.roll(block.number + 1);
        vm.prank(user);

        genesisVaultManager.deposit{value: depositAmount}();

        // Verify deposit succeeded
        assertEq(vHYPE.balanceOf(user), depositAmount);
        assertEq(address(stakingVault).balance, depositAmount);
    }

    function test_TransferToCoreAndDelegate_AllBalance_ZeroBalance() public {
        // No balance in staking vault
        assertEq(address(stakingVault).balance, 0);

        vm.roll(block.number + 1);

        vm.startPrank(operator);
        vm.expectRevert(GenesisVaultManager.ZeroAmount.selector);
        genesisVaultManager.transferToCoreAndDelegate();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Upgradeability                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        GenesisVaultManagerWithExtraFunction newImplementation = new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.prank(owner);
        genesisVaultManager.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(genesisVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(genesisVaultManager.vaultCapacity(), VAULT_CAPACITY);

        // Check that the extra function is available
        GenesisVaultManagerWithExtraFunction newProxy =
            GenesisVaultManagerWithExtraFunction(payable(address(genesisVaultManager)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner() public {
        GenesisVaultManagerWithExtraFunction newImplementation = new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        genesisVaultManager.upgradeToAndCall(address(newImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Tests: Ownership                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TransferOwnership_NewOwnerCanUpgrade() public {
        address originalOwner = owner;
        address newOwner = makeAddr("newOwner");

        // Transfer ownership using 2-step process
        vm.prank(originalOwner);
        roleRegistry.transferOwnership(newOwner);

        vm.prank(newOwner);
        roleRegistry.acceptOwnership();

        // Verify ownership has been transferred
        assertEq(roleRegistry.owner(), newOwner);

        // New owner upgrades the contract
        GenesisVaultManagerWithExtraFunction newImplementation = new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);
        vm.prank(newOwner);
        genesisVaultManager.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(genesisVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(address(genesisVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(genesisVaultManager.stakingVault()), address(stakingVault));

        // Check that the extra function is available
        GenesisVaultManagerWithExtraFunction newProxy =
            GenesisVaultManagerWithExtraFunction(payable(address(genesisVaultManager)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        GenesisVaultManagerWithExtraFunction anotherImplementation =
            new GenesisVaultManagerWithExtraFunction(HYPE_TOKEN_ID);
        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        genesisVaultManager.upgradeToAndCall(address(anotherImplementation), "");
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
