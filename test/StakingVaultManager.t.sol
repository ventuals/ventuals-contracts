// forge-lint: disable-start(mixed-case-variable)
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {StakingVaultManager} from "../src/StakingVaultManager.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {Vm} from "forge-std/Vm.sol";
import {Base} from "../src/Base.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Converters} from "../src/libraries/Converters.sol";
import {IStakingVault} from "../src/interfaces/IStakingVault.sol";

contract StakingVaultManagerTest is Test {
    using Converters for *;

    StakingVaultManager stakingVaultManager;
    RoleRegistry roleRegistry;
    VHYPE vHYPE;
    StakingVault stakingVault;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");

    address public validator = makeAddr("validator");
    address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID
    uint256 public constant MINIMUM_STAKE_BALANCE = 500_000 * 1e18; // 500k HYPE
    uint256 public constant MINIMUM_DEPOSIT_AMOUNT = 1e16; // 0.01 HYPE

    // Events
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);
    event EmergencyStakingDeposit(address indexed sender, uint256 amount, string purpose);

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

        // Deploy StakingVaultManager
        StakingVaultManager stakingVaultManagerImplementation = new StakingVaultManager(HYPE_TOKEN_ID);
        bytes memory stakingVaultManagerInitData = abi.encodeWithSelector(
            StakingVaultManager.initialize.selector,
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            validator,
            MINIMUM_STAKE_BALANCE,
            MINIMUM_DEPOSIT_AMOUNT
        );
        ERC1967Proxy stakingVaultManagerProxy =
            new ERC1967Proxy(address(stakingVaultManagerImplementation), stakingVaultManagerInitData);
        stakingVaultManager = StakingVaultManager(payable(stakingVaultManagerProxy));

        // Setup roles
        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), address(stakingVaultManager));
        roleRegistry.grantRole(roleRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock HYPE system contract
        MockHypeSystemContract mockHypeSystemContract = new MockHypeSystemContract();
        vm.etch(HYPE_SYSTEM_ADDRESS, address(mockHypeSystemContract).code);
        _mockSpotBalance(0);
        _mockDelegatorSummary(0);

        // Mock the core user exists check to return true
        _mockCoreUserExists(address(stakingVault), true);
        _mockCoreUserExists(user, true);

        // Set batch processing to enabled
        vm.prank(owner);
        stakingVaultManager.setBatchProcessingPaused(false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Initialization                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize() public view {
        assertEq(address(stakingVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(address(stakingVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(stakingVaultManager.stakingVault()), address(stakingVault));
        assertEq(stakingVaultManager.validator(), validator);
        assertEq(stakingVaultManager.minimumStakeBalance(), MINIMUM_STAKE_BALANCE);
        assertEq(stakingVaultManager.minimumDepositAmount(), MINIMUM_DEPOSIT_AMOUNT);
        assertEq(stakingVaultManager.HYPE_TOKEN_ID(), HYPE_TOKEN_ID);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        stakingVaultManager.initialize(
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            validator,
            MINIMUM_STAKE_BALANCE,
            MINIMUM_DEPOSIT_AMOUNT
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Deposit                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Deposit_EmptyVault() public {
        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        // Check that we minted 1:1 vHYPE when vault is empty
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);

        assertEq(userVHYPEBalance, depositAmount);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_VaultWithExistingStakeBalance() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k HYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // 1:1 ratio

        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateAboveOne() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 250_000 * 1e18; // 250k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 2

        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount / 2);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateBelowOne() public {
        uint256 existingBalance = 250_000 * 1e18; // 250k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 0.5

        uint256 depositAmount = 100_000 * 1e18; // 100k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount * 2);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount); // Should be exactly equal

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExactMinimumAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        vm.deal(user, MINIMUM_DEPOSIT_AMOUNT);
        vm.prank(user);
        stakingVaultManager.deposit{value: MINIMUM_DEPOSIT_AMOUNT}();

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
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: belowMinimumAmount}();
    }

    function test_Deposit_ZeroAmount() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: 0}();
    }

    function test_Deposit_RevertWhenContractPaused() public {
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply); // exchange rate = 1

        uint256 depositAmount = 500_000 * 1e18; // 500k HYPE

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.deposit{value: depositAmount}();

        // Check that no HYPE was transferred to staking vault (vault balance should remain 0)
        assertEq(address(stakingVault).balance, 0);

        // Check that no vHYPE was minted
        assertEq(vHYPE.balanceOf(user), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Queue Withdraw                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_QueueWithdraw_Success() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User has vHYPE balance
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, vhypeAmount);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        // Queue the withdraw
        uint256 withdrawId = stakingVaultManager.queueWithdraw(vhypeAmount);

        assertEq(withdrawId, 1);
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 1);
        assertEq(stakingVaultManager.getWithdraw(withdrawId).vhypeAmount, vhypeAmount);
        assertEq(stakingVaultManager.getWithdraw(withdrawId).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawId).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawId).claimed, false);

        // Verify vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount);
    }

    function test_QueueWithdraw_ZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.ZeroAmount.selector);
        stakingVaultManager.queueWithdraw(0);
    }

    function test_QueueWithdraw_InsufficientBalance() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User doesn't have any vHYPE balance
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        vm.expectRevert();
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_InsufficientAllowance() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User has vHYPE balance but no allowance
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, vhypeAmount);

        // Queue the withdraw without approval
        vm.startPrank(user);
        vm.expectRevert();
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_MultipleWithdraws() public {
        uint256 vhypeAmount1 = 50_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 25_000 * 1e18; // 25k vHYPE
        uint256 totalVhype = vhypeAmount1 + vhypeAmount2;

        // Setup: User has vHYPE balance
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, totalVhype);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), totalVhype);

        // Queue first withdraw
        uint256 withdrawId1 = stakingVaultManager.queueWithdraw(vhypeAmount1);

        // Queue second withdraw
        uint256 withdrawId2 = stakingVaultManager.queueWithdraw(vhypeAmount2);

        // Verify withdraw IDs are sequential
        assertEq(withdrawId1, 1);
        assertEq(withdrawId2, 2);

        // Verify withdraw queue length
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 2);

        // Verify withdraw queue contents
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).vhypeAmount, vhypeAmount1);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).claimed, false);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).vhypeAmount, vhypeAmount2);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).claimed, false);

        // Verify all vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), totalVhype);
    }

    function test_QueueWithdraw_WhenContractPaused() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User has vHYPE balance and approval
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, vhypeAmount);
        vm.prank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // Try to queue withdraw when paused
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Claim Withdraw                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ClaimWithdraw_Success() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        vm.warp(block.timestamp + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock spot balance check (vault has enough HYPE)
        _mockSpotBalance(uint64(vhypeAmount.to8Decimals()));

        // Mock spotSend call
        _mockAndExpectSpotSendCall(user, HYPE_TOKEN_ID, vhypeAmount.to8Decimals());

        // User claims the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimed, "Withdraw should be marked as claimed");
        assertEq(stakingVaultManager.totalHypeClaimed(), vhypeAmount, "Total HYPE claimed should match withdraw amount");
        assertEq(
            stakingVaultManager.totalHypeProcessed(), vhypeAmount, "Total HYPE processed should match withdraw amount"
        );
    }

    function test_ClaimWithdraw_NotAuthorized() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        address otherUser = makeAddr("otherUser");

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 7 days + 1);

        // Another user tries to claim the withdraw
        vm.prank(otherUser);
        vm.expectRevert(StakingVaultManager.NotAuthorized.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WithdrawCancelled() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mint vHYPE to owner and setup withdraw
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(owner, vhypeAmount);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Setup: User cancels the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // User tries to claim the cancelled withdraw
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawCancelled.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_AlreadyClaimed() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        vm.warp(block.timestamp + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock spot balance check (vault has enough HYPE)
        _mockSpotBalance(uint64(vhypeAmount.to8Decimals()));

        // Mock spotSend call
        _mockAndExpectSpotSendCall(user, HYPE_TOKEN_ID, vhypeAmount.to8Decimals());

        // User claims the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // User tries to claim again
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawClaimed.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_TooEarly() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 6 days);

        // User tries to claim too early
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawUnclaimable.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_ExactlySevenDays() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 7 days);

        // User tries to claim too early
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawUnclaimable.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_CoreUserDoesNotExist() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock spot balance check (vault has enough HYPE)
        _mockSpotBalance(uint64(vhypeAmount.to8Decimals()));

        // Core user does not exist
        address destination = makeAddr("destination");
        _mockCoreUserExists(destination, false);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.CoreUserDoesNotExist.selector, destination));
        stakingVaultManager.claimWithdraw(withdrawId, destination);
    }

    function test_ClaimWithdraw_InsufficientBalance() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock insufficient spot balance (only half of what's needed)
        _mockSpotBalance((vhypeAmount / 2).to8Decimals());

        // User tries to claim but vault has insufficient balance
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.InsufficientBalance.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WhenContractPaused() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        vm.warp(block.timestamp + 7 days + 1);

        // Mock spot balance check (vault has enough HYPE)
        _mockSpotBalance(vhypeAmount.to8Decimals());

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // User tries to claim when contract is paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WithSlashedBatch() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing (1:1 exchange rate)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 5e17); // 0.5 exchange rate

        // Fast-forward time
        vm.warp(block.timestamp + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock spot balance check (vault has enough HYPE)
        _mockSpotBalance(vhypeAmount.to8Decimals());

        // Mock spotSend call (should send half of the amount)
        _mockAndExpectSpotSendCall(user, HYPE_TOKEN_ID, vhypeAmount.to8Decimals() / 2);

        // User claims the slashed withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimed, "Withdraw should be marked as claimed");
        assertEq(
            stakingVaultManager.totalHypeClaimed(),
            vhypeAmount / 2,
            "Total HYPE claimed should match slashed withdraw amount"
        );
        assertEq(
            stakingVaultManager.totalHypeProcessed(),
            vhypeAmount / 2,
            "Total HYPE processed should match slashed withdraw amount"
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Cancel Withdraw                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_CancelWithdraw_Success() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mint vHYPE to owner so _setupWithdraw can transfer it
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(owner, vhypeAmount);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Verify initial state
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount);

        // User cancels the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // Verify the withdraw was cancelled
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.cancelled, "Withdraw should be marked as cancelled");

        // Verify vHYPE was refunded
        assertEq(vHYPE.balanceOf(user), vhypeAmount, "User should receive vHYPE refund");
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), 0, "Contract should have no vHYPE");
    }

    function test_CancelWithdraw_NotAuthorized() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        address otherUser = makeAddr("otherUser");

        // Setup: Mint vHYPE to owner so _setupWithdraw can transfer it
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(owner, vhypeAmount);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Another user tries to cancel the withdraw
        vm.prank(otherUser);
        vm.expectRevert(StakingVaultManager.NotAuthorized.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_AlreadyCancelled() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mint vHYPE to owner so _setupWithdraw can transfer it
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(owner, vhypeAmount);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // User cancels the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // User tries to cancel again
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawCancelled.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_AlreadyProcessed() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Mock batch processing calls
        _mockBatchProcessingCalls();

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify the withdraw was processed
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Withdraw should be processed");

        // User tries to cancel the processed withdraw
        vm.prank(user);
        vm.expectRevert(StakingVaultManager.WithdrawProcessed.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_WhenContractPaused() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE

        // Setup: Mint vHYPE to owner so _setupWithdraw can transfer it
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(owner, vhypeAmount);

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // User tries to cancel when contract is paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_InvalidWithdrawId() public {
        // Try to cancel a withdraw that doesn't exist
        vm.prank(user);
        vm.expectRevert(); // Should revert with array out of bounds or similar
        stakingVaultManager.cancelWithdraw(999);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Process Batch                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ProcessBatch_FirstBatch() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the first batch (should work without timing restrictions)
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        StakingVaultManager.Batch memory batch = stakingVaultManager.getBatch(0);
        assertEq(batch.vhypeProcessed, vhypeAmount, "Batch has incorrect amount of vHYPE");
        assertEq(batch.finalizedAt, 0, "Batch should not be finalized yet");
        assertEq(batch.snapshotExchangeRate, 1e18, "Batch has incorrect snapshot exchange rate");
        assertEq(batch.slashedExchangeRate, 0, "Batch should not have a slashed exchange rate");
        assertEq(batch.slashed, false, "Batch should not have been slashed");
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Batch length should be 1");
        assertEq(stakingVaultManager.currentBatchIndex(), 0, "Current batch index should still be 0");
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not change until batch is finalized");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Last processed withdraw ID should be 1");
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw.vhypeAmount, vhypeAmount, "Withdraw has incorrect amount of vHYPE");
        assertEq(withdraw.batchIndex, 0, "Withdraw has incorrect batch index");
        assertEq(withdraw.claimed, false, "Withdraw should not have been claimed");

        // Verify vHYPE state
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount, "vHYPE should still be in escrow");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
        assertEq(stakingVaultManager.totalHypeClaimed(), 0, "Total HYPE claimed should be 0");
    }

    function test_ProcessBatch_UnderMinimumStakeBalance() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE - vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the first batch (should work without timing restrictions)
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        StakingVaultManager.Batch memory batch = stakingVaultManager.getBatch(0);
        assertEq(batch.vhypeProcessed, 0, "Batch has incorrect amount of vHYPE");
        assertEq(batch.finalizedAt, 0, "Batch should not be finalized yet");
        assertEq(batch.snapshotExchangeRate, 1e18, "Batch has incorrect snapshot exchange rate");
        assertEq(batch.slashedExchangeRate, 0, "Batch should not have a slashed exchange rate");
        assertEq(batch.slashed, false, "Batch should not have been slashed");
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Batch length should be 1");
        assertEq(stakingVaultManager.currentBatchIndex(), 0, "Current batch index should still be 0");
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not change until batch is finalized");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw.vhypeAmount, vhypeAmount, "Withdraw has incorrect amount of vHYPE");
        assertEq(withdraw.batchIndex, type(uint256).max, "Withdraw should not have been assigned to a batch");
        assertEq(withdraw.claimed, false, "Withdraw should not have been claimed");

        // Verify vHYPE state
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount, "vHYPE should still be in escrow");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
        assertEq(stakingVaultManager.totalHypeClaimed(), 0, "Total HYPE claimed should be 0");
    }

    function test_ProcessBatch_WithTimingRestriction() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // User queues the first withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Process the first batch (should work without timing restrictions)
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the first batch
        stakingVaultManager.finalizeBatch();

        // User queues the second withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Try to process immediately (should fail due to timing restriction)
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.BatchNotReady.selector, block.timestamp + 1 days));
        stakingVaultManager.processBatch(type(uint256).max);

        // Advance time by 1 day + 1 second and try again (should succeed)
        vm.warp(block.timestamp + 1 days + 1);
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatchesLength(), 2, "Batch length should be 2");
        assertEq(stakingVaultManager.currentBatchIndex(), 1, "Current batch index should be 1 after finalizing batch 0");
        assertEq(
            stakingVaultManager.getBatch(1).vhypeProcessed,
            vhypeAmount / 2,
            "Batch 1 should have processed half of the vHYPE"
        );
        assertEq(stakingVaultManager.getBatch(1).finalizedAt, 0, "Batch 1 should not be finalized yet");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 2, "Last processed withdraw ID should be 2");
        StakingVaultManager.Withdraw memory withdraw0 = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw0.batchIndex, 0, "Withdraw 1 should be assigned to batch 0");
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(2);
        assertEq(withdraw1.batchIndex, 1, "Withdraw 1 should be assigned to batch 1");

        // Verify vHYPE escrow balance (batch 0 vHYPE was burned, batch 1 vHYPE is still escrowed)
        assertEq(
            vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount / 2, "Only batch 1 vHYPE should be in escrow"
        );

        // Verify process state (batch 0 was finalized, batch 1 is not)
        assertEq(
            stakingVaultManager.totalHypeProcessed(),
            vhypeAmount / 2,
            "Total HYPE processed should include finalized batch 0"
        );
    }

    function test_ProcessBatch_WhenBatchProcessingPaused() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Set batch processing to paused
        vm.prank(owner);
        stakingVaultManager.setBatchProcessingPaused(true);

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Batch processing is paused by default, so this should fail
        vm.expectRevert(StakingVaultManager.BatchProcessingPaused.selector);
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_WhenContractPaused() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Pause the entire contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // Try to process batch when contract is paused
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_InsufficientCapacity() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE (more than available capacity)

        // Setup: Mock minimum stake balance (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a large withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process batch (should create empty batch since no withdraws can be processed)
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, 0, "Batch should have processed 0 vHYPE");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Withdraw should still be in queue");
        assertEq(
            stakingVaultManager.getWithdraw(1).batchIndex,
            type(uint256).max,
            "Withdraw should not be assigned to a batch"
        );

        // Verify vHYPE escrow balance
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount, "vHYPE should still be in contract");

        // Verify process state
        assertEq(stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0");
    }

    function test_ProcessBatch_PartialProcessing() public {
        uint256 vhypeAmount1 = 50_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 100_000 * 1e18; // 100k vHYPE (this one won't fit)
        address user2 = makeAddr("user2");

        // Setup: Mock stake balance (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 100_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Two users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user2, vhypeAmount2);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // Process batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, vhypeAmount1, "Batch should have processed 50k vHYPE");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Last processed withdraw ID should be 1");
        assertEq(stakingVaultManager.getWithdraw(1).batchIndex, 0, "Withdraw 1 should be assigned to batch 0");
        assertEq(
            stakingVaultManager.getWithdraw(2).batchIndex,
            type(uint256).max,
            "Withdraw 1 should not be assigned to a batch"
        );

        // Verify vHYPE state (vHYPE is not burned until finalizeBatch())
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not change until batch is finalized");
        assertEq(
            vHYPE.balanceOf(address(stakingVaultManager)),
            vhypeAmount1 + vhypeAmount2,
            "Both withdraw vHYPE amounts should still be escrowed"
        );

        // Verify process state (totalHypeProcessed is not updated until finalizeBatch())
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
    }

    function test_ProcessBatch_EmptyQueue() public {
        // Setup: Mock sufficient balance
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 200_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Process batch with no withdraws in queue
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Batch length should be 1");
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, 0, "Batch should have processed 0 vHYPE");
        assertEq(stakingVaultManager.getBatch(0).finalizedAt, 0, "Batch should not be finalized yet");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");

        // Verify vHYPE state
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not have changed");

        // Verify process state
        assertEq(stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0");
    }

    function test_ProcessBatch_CancelledWithdrawsSkipped() public {
        uint256 vhypeAmount1 = 50_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 75_000 * 1e18; // 75k vHYPE
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 200_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // Setup: Two users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user2, vhypeAmount2);

        // Cancel the first withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(1);

        // Process batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, vhypeAmount2, "Batch should have processed 75k vHYPE");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 2, "Last processed withdraw ID should be 2");
        assertEq(stakingVaultManager.nextWithdrawId(), 3, "Next withdraw ID should be 3");

        // Verify vHYPE state
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not change until batch is finalized");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
    }

    function test_ProcessBatch_MultipleWithdraws() public {
        uint256 vhypeAmount1 = 25_000 * 1e18; // 25k vHYPE
        uint256 vhypeAmount2 = 35_000 * 1e18; // 35k vHYPE
        uint256 vhypeAmount3 = 40_000 * 1e18; // 40k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Setup: Mock sufficient balance
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 200_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Mock the calls that batch processing makes
        _mockBatchProcessingCalls();

        // Setup: Three users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user2, vhypeAmount2);
        _setupWithdraw(user3, vhypeAmount3);

        // Process batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(
            stakingVaultManager.getBatch(0).vhypeProcessed,
            vhypeAmount1 + vhypeAmount2 + vhypeAmount3,
            "Batch should have processed 100k vHYPE"
        );

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Last processed withdraw ID should be 3");

        // Verify vHYPE state
        assertEq(vHYPE.totalSupply(), totalBalance, "vHYPE supply should not change until batch is finalized");
        assertEq(
            vHYPE.balanceOf(address(stakingVaultManager)),
            vhypeAmount1 + vhypeAmount2 + vhypeAmount3,
            "All vHYPE should still be in escrow"
        );

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Finalize Batch                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FinalizeBatch_CanFinalizeWhenUnderMinimumStakeBalance() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE withdraw

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        // Initial balance: minimumStakeBalance (500k) + 100k (for withdraw) = 600k
        uint256 totalBalance = MINIMUM_STAKE_BALANCE - vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        _expectNoStakeCall();
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Verify state
        assertEq(stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
    }

    function test_FinalizeBatch_DustHypeAmountNotTransferred() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits (exchange rate = 1)
        uint256 dustHypeAmount = 0.5e10; // dust
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits + dustHypeAmount);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits + dustHypeAmount}();

        // Expect a transfer to HyperCore call with the dust amount removed
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        _expectNoStakeCall();
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsEqualWithdraws() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Only expect a transfer to HyperCore call
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        _expectNoStakeCall();
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsGreaterThanWithdraws() public {
        uint256 vhypeAmount = 30_000 * 1e18; // 30k vHYPE withdraw
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Mock and expect calls for deposits > withdraws scenario

        // First call: transfer all deposits to HyperCore
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        _mockAndExpectStakingDepositCall((hypeDeposits - vhypeAmount).to8Decimals());
        _mockAndExpectTokenDelegateCall(
            validator, (hypeDeposits - vhypeAmount).to8Decimals(), false /* isUndelegate */
        );

        // No undelegate call or staking withdraw call expected
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsLessThanWithdraws() public {
        uint256 vhypeAmount = 70_000 * 1e18; // 70k vHYPE withdraw
        uint256 hypeDeposits = 30_000 * 1e18; // 30k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Mock and expect calls for deposits < withdraws scenario

        // First call: transfer all deposits to core
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());

        // Second call: undelegate shortfall amount (use CoreWriter helper)
        _mockAndExpectTokenDelegateCall(validator, (vhypeAmount - hypeDeposits).to8Decimals(), true /* isUndelegate */ );

        // Third call: withdraw shortfall from staking (use CoreWriter helper)
        _mockAndExpectStakingWithdrawCall((vhypeAmount - hypeDeposits).to8Decimals());

        // No staking deposit or delegate call expected
        _expectNoStakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterSwitchValidatorInSameBlock() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE
        address newValidator = makeAddr("newValidator");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());
        _mockAndExpectTokenDelegateCall(validator, totalBalance.to8Decimals(), true);
        _mockAndExpectTokenDelegateCall(newValidator, totalBalance.to8Decimals(), false);

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Switch validator
        vm.prank(owner);
        stakingVaultManager.switchValidator(newValidator);

        // Finalize the batch
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterEmergencyStakingWithdrawInSameBlock() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Mock balances
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(totalBalance.to8Decimals());
        _mockAndExpectStakingWithdrawCall(totalBalance.to8Decimals());
        _mockAndExpectTokenDelegateCall(stakingVaultManager.validator(), totalBalance.to8Decimals(), true);

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Emergency withdraw
        vm.prank(owner);
        stakingVaultManager.emergencyStakingWithdraw(totalBalance, "Emergency withdraw");

        // Finalize the batch
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterSlash() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Apply slash to the batch (50% slash)
        _mockDelegatorSummary((totalBalance / 2).to8Decimals());

        // Attempt to finalize should revert due to insufficient balance
        vm.expectRevert(StakingVaultManager.NotEnoughBalance.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CanFinalizeAfterSlashIsApplied() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Apply slash to the batch (50% slash)
        _mockDelegatorSummary((totalBalance / 2).to8Decimals());

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Process the batch again
        stakingVaultManager.processBatch(type(uint256).max);

        // Mock and expect calls for for the deposit
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        _mockAndExpectStakingDepositCall(hypeDeposits.to8Decimals());
        _mockAndExpectTokenDelegateCall(validator, hypeDeposits.to8Decimals(), false /* isUndelegate */ );

        // Finalize the batch
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_ZeroDeposits() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE withdraw

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Mock and expect calls for zero deposits scenario

        // Should undelegate the full withdraw amount
        _mockAndExpectTokenDelegateCall(validator, vhypeAmount.to8Decimals(), true /* isUndelegate */ );

        // Should withdraw the full amount from staking
        _mockAndExpectStakingWithdrawCall(vhypeAmount.to8Decimals());

        // No staking deposit or delegate call expected
        _expectNoStakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_ZeroWithdraws() public {
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits

        // Setup: Mock sufficient balance for processing (exchange rate = 1)
        uint256 totalBalance = MINIMUM_STAKE_BALANCE;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Setup: Mock vault balance with deposits but no withdraws
        vm.deal(address(stakingVault), hypeDeposits);

        // Mock and expect calls for zero withdraws scenario

        // First call: transfer all deposits to core
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());

        // Second call: stake all deposits
        _mockAndExpectStakingDepositCall(hypeDeposits.to8Decimals());

        // Third call: delegate all deposits
        _mockAndExpectTokenDelegateCall(validator, hypeDeposits.to8Decimals(), false /* isUndelegate */ );

        // No undelegate call or staking withdraw call expected
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_ZeroDepositsZeroWithdraws() public {
        // Setup: Mock sufficient balance for processing
        uint256 totalBalance = MINIMUM_STAKE_BALANCE;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // No HyperCore deposit expected
        vm.expectCall(address(HYPE_SYSTEM_ADDRESS), abi.encode(), 0);

        _expectNoStakeCall();
        _expectNoUnstakeCall();

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
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

        uint256 balance = stakingVaultManager.stakingAccountBalance();
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

        uint256 balance = stakingVaultManager.spotAccountBalance();
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

        uint256 totalBalance = stakingVaultManager.totalBalance();
        // 1e18 (staking) + 2e18 (spot) + 1e18 (contract balance) = 4e18
        assertEq(totalBalance, 4e18);
    }

    function test_TotalBalance_WithReservedHypeForWithdraws() public {
        uint256 vhypeWithdrawAmount = 100_000 * 1e18;

        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeWithdrawAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeWithdrawAmount);

        // Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Test totalBalance after processing (should subtract reservedHypeForWithdraws)
        assertEq(stakingVaultManager.totalBalance(), MINIMUM_STAKE_BALANCE);

        // Verify the reserved amount calculation
        assertEq(stakingVaultManager.totalHypeProcessed(), vhypeWithdrawAmount);
        assertEq(stakingVaultManager.totalHypeClaimed(), 0);

        // Mock a 50% slash
        _mockDelegatorSummary((totalBalance / 2).to8Decimals());

        // Apply the slash
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 0.5e18);

        // Test totalBalance after slash
        // 600k HYPE slashed to 300k HYPE
        // 100k HYPE withdraw reserve slashed to 50k HYPE
        // So we expect 250k HYPE in total balance
        assertEq(stakingVaultManager.totalBalance(), 250_000 * 1e18);
    }

    function test_TotalBalance_ReservedHypeForWithdrawsGreaterThanAccountBalance() public {
        uint256 vhypeWithdrawAmount = 100_000 * 1e18;

        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeWithdrawAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeWithdrawAmount);

        // Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Test totalBalance after processing (should subtract reservedHypeForWithdraws)
        assertEq(stakingVaultManager.totalBalance(), MINIMUM_STAKE_BALANCE);

        // Verify the reserved amount calculation
        assertEq(stakingVaultManager.totalHypeProcessed(), vhypeWithdrawAmount);
        assertEq(stakingVaultManager.totalHypeClaimed(), 0);

        // Mock a 100% slash
        _mockDelegatorSummary(0);

        // Test totalBalance after slash
        // 600k HYPE slashed to 300k HYPE
        // 100k HYPE withdraw reserve slashed to 50k HYPE
        // So we expect 250k HYPE in total balance
        vm.expectRevert(
            abi.encodeWithSelector(StakingVaultManager.AccountBalanceLessThanReservedHypeForWithdraws.selector)
        );
        stakingVaultManager.totalBalance();
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
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, 2e18);

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
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
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, 8e18);

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
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
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, 2e18); // 2 vHYPE tokens

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
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

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
        assertEq(exchangeRate, 1e18);
    }

    function test_ExchangeRate_BalanceMoreThanSupply(uint256 totalBalance, uint256 vHYPESupply) public {
        vm.assume(totalBalance <= 1_000_000_000e18 && vHYPESupply <= 1_000_000_000e18);
        /// TODO: Fix fuzz failure here.
        vm.assume(totalBalance >= 1e10);
        vm.assume(vHYPESupply > 0);
        vm.assume(totalBalance > vHYPESupply);
        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
        assertGt(exchangeRate, 1e18); // exchange rate >= 1
    }

    function test_ExchangeRate_BalanceLessThanSupply(uint256 totalBalance, uint256 vHYPESupply) public {
        vm.assume(totalBalance <= 1_000_000_000e18 && vHYPESupply <= 1_000_000_000e18);
        vm.assume(totalBalance > 0);
        vm.assume(vHYPESupply > 0);
        vm.assume(totalBalance < vHYPESupply);
        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        uint256 exchangeRate = stakingVaultManager.exchangeRate();
        assertLt(exchangeRate, 1e18); // exchange rate <= 1
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: HYPETovHYPE and vHYPEtoHYPE Functions       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_HYPETovHYPE_ExchangeRateAboveOne() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 1e18);
    }

    function test_HYPETovHYPE_ExchangeRateBelowOne() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 4e18 /* 4 vHYPE */ ); // exchange rate = 0.5
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 4e18);
    }

    function test_HYPETovHYPE_ZeroAmount() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(stakingVaultManager.HYPETovHYPE(0), 0);
    }

    function test_HYPETovHYPE_ZeroExchangeRate_ZeroBalance() public {
        _mockBalancesForExchangeRate(0, /* 0 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 0
        assertEq(stakingVaultManager.HYPETovHYPE(1e18), 0);
    }

    function test_HYPETovHYPE_OneExchangeRate_ZeroSupply() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 0 /* 0 vHYPE */ ); // exchange rate = 1
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateAboveOne() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateBelowOne() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 4e18 /* 4 vHYPE */ ); // exchange rate = 0.5
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 0.5e18);
    }

    function test_vHYPEtoHYPE_ZeroAmount() public {
        _mockBalancesForExchangeRate(4e18, /* 4 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 2
        assertEq(stakingVaultManager.vHYPEtoHYPE(0), 0);
    }

    function test_vHYPEtoHYPE_ZeroExchangeRate_ZeroBalance() public {
        _mockBalancesForExchangeRate(0, /* 0 HYPE */ 2e18 /* 2 vHYPE */ ); // exchange rate = 0
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 0);
    }

    function test_vHYPEtoHYPE_ZeroExchangeRate_ZeroSupply() public {
        _mockBalancesForExchangeRate(2e18, /* 2 HYPE */ 0 /* 0 vHYPE */ ); // exchange rate = 1
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 1e18);
    }

    function test_HYPETovHYPE_vHYPEtoHYPE_Roundtrip(
        uint256 totalBalance,
        uint256 vHYPESupply,
        uint256 hypeAmountToConvert
    ) public {
        totalBalance = bound(totalBalance, 1, 1_000_000_000e18);
        vHYPESupply = bound(vHYPESupply, 1, 1_000_000_000e18);
        hypeAmountToConvert = bound(hypeAmountToConvert, 1, 2_000_000 * 1e18 - 1);

        _mockBalancesForExchangeRate(totalBalance, vHYPESupply);

        // Here we bound the exchange rate to be between 0 and 1e15. Otherwise, we'll see large precision loss
        // with extremely high exchange rates.
        //
        // Extremely high exchange rates are very unlikely to occur in practice. 1e15 is a very geneerous upper
        // bound for the exchange rate (it's 1 million * 1 million, which would only occur if we've earned
        // 1 million HYPE for every vHYPE minted).
        uint256 exchangeRate = stakingVaultManager.exchangeRate();
        vm.assume(exchangeRate > 0 && exchangeRate < 1e15);

        uint256 vHYPEAmount = stakingVaultManager.HYPETovHYPE(hypeAmountToConvert);
        uint256 convertedBackHYPE = stakingVaultManager.vHYPEtoHYPE(vHYPEAmount);

        // Allow for 1-2 wei difference due to rounding
        assertApproxEqAbs(convertedBackHYPE, hypeAmountToConvert, 2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          Tests: Minimum Stake Balance (Only Owner)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMinimumStakeBalance_OnlyOwner() public {
        uint256 newMinimumStakeBalance = 600_000 * 1e18;

        vm.prank(owner);
        stakingVaultManager.setMinimumStakeBalance(newMinimumStakeBalance);

        assertEq(stakingVaultManager.minimumStakeBalance(), newMinimumStakeBalance);
    }

    function test_SetMinimumStakeBalance_NotOwner() public {
        uint256 newMinimumStakeBalance = 600_000 * 1e18;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setMinimumStakeBalance(newMinimumStakeBalance);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       Tests: Set Minimum Deposit Amount (Only Owner)       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMinimumDepositAmount_OnlyOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.prank(owner);
        stakingVaultManager.setMinimumDepositAmount(newMinimumAmount);

        assertEq(stakingVaultManager.minimumDepositAmount(), newMinimumAmount);
    }

    function test_SetMinimumDepositAmount_NotOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setMinimumDepositAmount(newMinimumAmount);
    }

    function test_SetMinimumDepositAmount_UpdatesDepositValidation() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE
        uint256 belowNewMinimum = newMinimumAmount - 1; // 1 wei below new minimum

        // Set new minimum amount
        vm.prank(owner);
        stakingVaultManager.setMinimumDepositAmount(newMinimumAmount);

        // Mock balances for deposit
        uint256 existingBalance = 500_000 * 1e18; // 500k HYPE
        uint256 existingSupply = 500_000 * 1e18; // 500k vHYPE
        _mockBalancesForExchangeRate(existingBalance, existingSupply);

        // Try to deposit below new minimum - should fail
        vm.deal(user, belowNewMinimum);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: belowNewMinimum}();

        // Deposit exactly the new minimum - should succeed
        vm.deal(user, newMinimumAmount);
        stakingVaultManager.deposit{value: newMinimumAmount}();

        // Verify deposit succeeded
        assertEq(vHYPE.balanceOf(user), newMinimumAmount);
        assertEq(address(stakingVault).balance, newMinimumAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: Set Batch Processing Paused (Only Owner)    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetBatchProcessingPaused_OnlyOwner() public {
        // Owner can unpause processing
        vm.prank(owner);
        stakingVaultManager.setBatchProcessingPaused(false);
        assertFalse(stakingVaultManager.isBatchProcessingPaused(), "Batch processing should be unpaused");

        // Owner can pause processing
        vm.prank(owner);
        stakingVaultManager.setBatchProcessingPaused(true);
        assertTrue(stakingVaultManager.isBatchProcessingPaused(), "Batch processing should be paused");
    }

    function test_SetBatchProcessingPaused_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setBatchProcessingPaused(false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Reset Batch (Only Owner)               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ResetBatch_Success() public {
        uint256 vhypeAmount1 = 50_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 30_000 * 1e18; // 30k vHYPE
        uint256 vhypeAmount3 = 20_000 * 1e18; // 20k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Setup: Mock sufficient balance
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 200_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Three users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user2, vhypeAmount2);
        _setupWithdraw(user3, vhypeAmount3);

        // Process first two withdrawals
        stakingVaultManager.processBatch(2);

        // Verify batch state before reset
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Should have 1 batch");
        assertEq(
            stakingVaultManager.getBatch(0).vhypeProcessed,
            vhypeAmount1 + vhypeAmount2,
            "Batch should have 80k vHYPE processed"
        );
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 2, "Last processed withdraw ID should be 2");
        assertEq(stakingVaultManager.getWithdraw(1).batchIndex, 0, "First withdraw should be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(2).batchIndex, 0, "Second withdraw should be in batch 0");
        assertEq(
            stakingVaultManager.getWithdraw(3).batchIndex,
            type(uint256).max,
            "Third withdraw should not be assigned yet"
        );

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Verify withdrawals were reset
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be reset to 0");
        assertEq(
            stakingVaultManager.getWithdraw(1).batchIndex, type(uint256).max, "First withdraw should be unassigned"
        );
        assertEq(
            stakingVaultManager.getWithdraw(2).batchIndex, type(uint256).max, "Second withdraw should be unassigned"
        );
        assertEq(
            stakingVaultManager.getWithdraw(3).batchIndex,
            type(uint256).max,
            "Third withdraw should still be unassigned"
        );

        // Verify vHYPE is still escrowed
        assertEq(
            vHYPE.balanceOf(address(stakingVaultManager)),
            vhypeAmount1 + vhypeAmount2 + vhypeAmount3,
            "All vHYPE should still be escrowed"
        );

        // Verify batch has not been removed
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Batch should not be removed until finalized");
    }

    function test_ResetBatch_WithCancelledWithdrawals() public {
        uint256 vhypeAmount1 = 50_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 30_000 * 1e18; // 30k vHYPE (will be cancelled)
        uint256 vhypeAmount3 = 20_000 * 1e18; // 20k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Setup: Mock sufficient balance
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + 200_000 * 1e18;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Three users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user2, vhypeAmount2);
        _setupWithdraw(user3, vhypeAmount3);

        // Cancel the second withdrawal
        vm.prank(user2);
        stakingVaultManager.cancelWithdraw(withdrawId2);

        // Process withdrawals
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify state before reset
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Should have processed all 3 withdraw IDs");
        assertEq(
            stakingVaultManager.getBatch(0).vhypeProcessed,
            vhypeAmount1 + vhypeAmount3,
            "Only non-cancelled withdrawals processed"
        );

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Verify withdrawals were reset
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be reset");
        assertEq(
            stakingVaultManager.getWithdraw(1).batchIndex, type(uint256).max, "First withdraw should be unassigned"
        );
        assertEq(
            stakingVaultManager.getWithdraw(3).batchIndex, type(uint256).max, "Third withdraw should be unassigned"
        );
        assertEq(
            stakingVaultManager.getWithdraw(2).batchIndex,
            type(uint256).max,
            "Second (cancelled) withdraw should remain unassigned"
        );
    }

    function test_ResetBatch_NothingToReset() public {
        // Try to reset when no batch exists
        vm.prank(owner);
        vm.expectRevert(StakingVaultManager.NothingToReset.selector);
        stakingVaultManager.resetBatch(type(uint256).max);
    }

    function test_ResetBatch_CannotResetFinalizedBatch() public {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockBatchProcessingCalls();

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Try to reset - should fail
        vm.startPrank(owner);
        vm.expectRevert(StakingVaultManager.NothingToReset.selector);
        stakingVaultManager.resetBatch(type(uint256).max);
    }

    function test_ResetBatch_NotOwner() public {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Try to reset as non-owner
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.resetBatch(type(uint256).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          Tests: Finalize Reset Batch (Only Owner)          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FinalizeResetBatch_Success() public {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch was created
        uint256 batchIndex = stakingVaultManager.currentBatchIndex();
        assertEq(stakingVaultManager.getBatch(batchIndex).vhypeProcessed, vhypeAmount);

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Verify batch is fully reset
        assertEq(stakingVaultManager.getBatch(batchIndex).vhypeProcessed, 0);

        // Finalize the reset
        vm.prank(owner);
        stakingVaultManager.finalizeResetBatch();

        // Verify batch was removed - batches.length should be 0
        assertEq(stakingVaultManager.getBatchesLength(), 0);
    }

    function test_FinalizeResetBatch_FailsWithPartialReset() public {
        uint256 vhypeAmount1 = 30_000 * 1e18;
        uint256 vhypeAmount2 = 20_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount1 + vhypeAmount2;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Queue and process two withdrawals
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user, vhypeAmount2);
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch has both withdrawals
        uint256 batchIndex = stakingVaultManager.currentBatchIndex();
        assertEq(stakingVaultManager.getBatch(batchIndex).vhypeProcessed, vhypeAmount1 + vhypeAmount2);

        // Reset only one withdrawal
        vm.prank(owner);
        stakingVaultManager.resetBatch(1);

        // Verify batch is partially reset
        assertEq(stakingVaultManager.getBatch(batchIndex).vhypeProcessed, vhypeAmount1);

        // Try to finalize - should fail because vhypeProcessed > 0
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.InvalidBatch.selector, batchIndex));
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_FailsWithNoBatch() public {
        // Try to finalize when no batch exists
        vm.prank(owner);
        vm.expectRevert(StakingVaultManager.NothingToFinalize.selector);
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_FailsWithFinalizedBatch() public {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);
        _mockDelegations(validator, totalBalance.to8Decimals());

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Mock finalization calls
        _mockAndExpectTokenDelegateCall(validator, vhypeAmount.to8Decimals(), true);
        _mockAndExpectStakingWithdrawCall(vhypeAmount.to8Decimals());

        // Finalize the batch normally
        stakingVaultManager.finalizeBatch();

        // Try to finalize reset - should fail because currentBatchIndex moved past the finalized batch
        // and there's no current batch to reset
        vm.prank(owner);
        vm.expectRevert(StakingVaultManager.NothingToFinalize.selector);
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_NotOwner() public {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Setup
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Try to finalize as non-owner
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.finalizeResetBatch();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*            Tests: Switch Validator (Only Owner)            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SwitchValidator_OnlyOwner() public {
        address newValidator = makeAddr("newValidator");
        uint256 amount = 100_000 * 1e18; // 100k HYPE

        // Current validator should be defaultValidator
        assertEq(stakingVaultManager.validator(), validator);

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegations(validator, amount.to8Decimals());

        // Mock the undelegate call (from current validator)
        _mockAndExpectTokenDelegateCall(validator, amount.to8Decimals(), true);

        // Mock the delegate call (to new validator)
        _mockAndExpectTokenDelegateCall(newValidator, amount.to8Decimals(), false);

        vm.prank(owner);
        stakingVaultManager.switchValidator(newValidator);

        // Verify validator was updated
        assertEq(stakingVaultManager.validator(), newValidator);
    }

    function test_SwitchValidator_NotOwner() public {
        address newValidator = makeAddr("newValidator");
        uint256 amount = 100_000 * 1e18;

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegations(validator, amount.to8Decimals());

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.switchValidator(newValidator);
    }

    function test_SwitchValidator_SameValidator() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegations(validator, amount.to8Decimals());

        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.RedelegateToSameValidator.selector);
        stakingVaultManager.switchValidator(validator);
    }

    function test_SwitchValidator_StakeLockedUntilFuture() public {
        address newValidator = makeAddr("newValidator");
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegationsWithLock(validator, amount.to8Decimals(), futureTimestamp);

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVaultManager.switchValidator(newValidator);
    }

    function test_SwitchValidator_StakeUnlockedAtExactTimestamp() public {
        address newValidator = makeAddr("newValidator");
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 currentTimestamp = uint64(block.timestamp); // Exact current timestamp

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegationsWithLock(validator, amount.to8Decimals(), currentTimestamp);

        // Mock the undelegate call (from current validator)
        _mockAndExpectTokenDelegateCall(validator, amount.to8Decimals(), true);
        // Mock the delegate call (to new validator)
        _mockAndExpectTokenDelegateCall(newValidator, amount.to8Decimals(), false);

        vm.prank(owner);
        stakingVaultManager.switchValidator(newValidator);

        // Verify validator was updated
        assertEq(stakingVaultManager.validator(), newValidator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             Tests: Emergency Withdraw (Only Owner)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_EmergencyStakingWithdraw_OnlyOwner() public {
        uint64 withdrawWeiAmount = 100_000 * 1e8; // 100k HYPE (in 8 decimals)
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        _mockDelegatorSummary(withdrawWeiAmount);
        _mockDelegations(withdrawWeiAmount);
        _mockAndExpectStakingWithdrawCall(withdrawWeiAmount);
        _mockAndExpectTokenDelegateCall(stakingVaultManager.validator(), withdrawWeiAmount, true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyStakingWithdraw(owner, withdrawAmount, "Emergency staking withdraw");
        stakingVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.emergencyStakingWithdraw(1_000_000 * 1e18, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_InsufficientBalance() public {
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        _mockDelegatorSummary(50_000 * 1e8); // 50k HYPE delegated (in 8 decimals)
        _mockDelegations(50_000 * 1e8);

        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_ZeroAmount() public {
        _mockDelegatorSummary(uint64(1_000_000 * 1e8)); // 1M HYPE delegated
        _mockDelegations(uint64(1_000_000 * 1e8));

        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVaultManager.emergencyStakingWithdraw(0, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_InsufficientDelegatedBalance() public {
        uint256 requestedAmount = 100_000 * 1e18; // 100k HYPE
        uint256 delegatedAmount = 50_000 * 1e18; // Only 50k HYPE delegated

        _mockDelegatorSummary(delegatedAmount.to8Decimals());
        _mockDelegations(validator, delegatedAmount.to8Decimals());

        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVaultManager.emergencyStakingWithdraw(requestedAmount, "Emergency withdraw");
    }

    function test_EmergencyStakingWithdraw_StakeLockedUntilFuture() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegationsWithLock(validator, amount.to8Decimals(), futureTimestamp);

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVaultManager.emergencyStakingWithdraw(amount, "Emergency withdraw");
    }

    function test_EmergencyStakingWithdraw_StakeUnlockedAtExactTimestamp() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 currentTimestamp = uint64(block.timestamp); // Exact current timestamp

        _mockDelegatorSummary(amount.to8Decimals());
        _mockDelegationsWithLock(validator, amount.to8Decimals(), currentTimestamp);

        _mockAndExpectTokenDelegateCall(validator, amount.to8Decimals(), true);
        _mockAndExpectStakingWithdrawCall(amount.to8Decimals());

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyStakingWithdraw(owner, amount, "Emergency withdraw");
        stakingVaultManager.emergencyStakingWithdraw(amount, "Emergency withdraw");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             Tests: Emergency Deposit (Only Owner)          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_EmergencyStakingDeposit() public {
        uint256 depositAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)
        uint64 depositWeiAmount = depositAmount.to8Decimals();

        _mockAndExpectTokenDelegateCall(stakingVaultManager.validator(), depositWeiAmount, false);
        _mockAndExpectStakingDepositCall(depositWeiAmount);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyStakingDeposit(owner, depositAmount, "Emergency staking deposit");
        stakingVaultManager.emergencyStakingDeposit(depositAmount, "Emergency staking deposit");
    }

    function test_EmergencyStakingDeposit_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.emergencyStakingDeposit(1_000_000 * 1e18, "Emergency staking deposit");
    }

    function test_EmergencyStakingDeposit_ZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVaultManager.emergencyStakingDeposit(0, "Emergency staking deposit");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Upgradeability                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.prank(owner);
        stakingVaultManager.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(stakingVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(stakingVaultManager.minimumStakeBalance(), MINIMUM_STAKE_BALANCE);

        // Check that the extra function is available
        StakingVaultManagerWithExtraFunction newProxy =
            StakingVaultManagerWithExtraFunction(payable(address(stakingVaultManager)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner() public {
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction(HYPE_TOKEN_ID);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.upgradeToAndCall(address(newImplementation), "");
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
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction(HYPE_TOKEN_ID);
        vm.prank(newOwner);
        stakingVaultManager.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(stakingVaultManager.roleRegistry()), address(roleRegistry));
        assertEq(address(stakingVaultManager.vHYPE()), address(vHYPE));
        assertEq(address(stakingVaultManager.stakingVault()), address(stakingVault));

        // Check that the extra function is available
        StakingVaultManagerWithExtraFunction newProxy =
            StakingVaultManagerWithExtraFunction(payable(address(stakingVaultManager)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        StakingVaultManagerWithExtraFunction anotherImplementation =
            new StakingVaultManagerWithExtraFunction(HYPE_TOKEN_ID);
        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        stakingVaultManager.upgradeToAndCall(address(anotherImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Apply Slash (Only Owner)               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ApplySlash_ValidBatch() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Check initial state
        StakingVaultManager.Batch memory batchBefore = stakingVaultManager.getBatch(0);
        assertEq(stakingVaultManager.totalHypeProcessed(), vhypeAmount);

        // Apply slash - 50% slash (0.5 exchange rate)
        uint256 slashedExchangeRate = 5e17; // 0.5
        vm.prank(owner);
        stakingVaultManager.applySlash(0, slashedExchangeRate);

        // Verify batch was slashed
        StakingVaultManager.Batch memory batchAfter = stakingVaultManager.getBatch(0);
        assertTrue(batchAfter.slashed);
        assertEq(batchAfter.slashedExchangeRate, slashedExchangeRate);
        assertEq(batchAfter.snapshotExchangeRate, batchBefore.snapshotExchangeRate); // Original rate unchanged

        // Verify totalHypeProcessed was updated correctly
        assertEq(stakingVaultManager.totalHypeProcessed(), 50_000 * 1e18);
    }

    function test_ApplySlash_InvalidBatch() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(StakingVaultManager.InvalidBatch.selector, 999));
        stakingVaultManager.applySlash(999, 5e17);
    }

    function test_ApplySlash_NotOwner() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Try to apply slash as non-owner
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.applySlash(0, 5e17);
    }

    function test_ApplySlash_ZeroSlashedExchangeRate() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Apply slash with zero exchange rate (100% slash)
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 0);

        // Verify batch was slashed to zero
        StakingVaultManager.Batch memory batch = stakingVaultManager.getBatch(0);
        assertTrue(batch.slashed);
        assertEq(batch.slashedExchangeRate, 0);

        // Verify totalHypeProcessed was updated correctly
        assertEq(stakingVaultManager.totalHypeProcessed(), 0);
    }

    function test_ApplySlash_MultipleBatches() public {
        uint256 vhypeAmount = 50_000 * 1e18; // 50k vHYPE
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + (vhypeAmount * 2);
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: Create first batch
        _mockBatchProcessingCalls();
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the first batch
        stakingVaultManager.finalizeBatch();

        // Fast forward by 1 day
        vm.warp(block.timestamp + 1 days + 1);

        // Setup: Create second batch
        _mockBatchProcessingCalls();
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the second batch
        stakingVaultManager.finalizeBatch();

        // Apply different slashes to different batches
        vm.startPrank(owner);
        stakingVaultManager.applySlash(0, 5e17); // 50% slash on batch 0
        stakingVaultManager.applySlash(1, 2e17); // 80% slash on batch 1

        // Verify both batches were slashed correctly
        StakingVaultManager.Batch memory batch0 = stakingVaultManager.getBatch(0);
        StakingVaultManager.Batch memory batch1 = stakingVaultManager.getBatch(1);

        assertTrue(batch0.slashed);
        assertEq(batch0.slashedExchangeRate, 5e17);

        assertTrue(batch1.slashed);
        assertEq(batch1.slashedExchangeRate, 2e17);

        // Verify totalHypeProcessed was updated correctly
        assertEq(stakingVaultManager.totalHypeProcessed(), 25_000 * 1e18 + 10_000 * 1e18);
    }

    function test_ApplySlash_ReapplySlash() public {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE
        uint256 totalBalance = MINIMUM_STAKE_BALANCE + vhypeAmount;
        _mockBalancesForExchangeRate(totalBalance, totalBalance);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        _mockBatchProcessingCalls();
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Apply first slash
        vm.startPrank(owner);
        stakingVaultManager.applySlash(0, 5e17); // 0.5 exchange rate
        stakingVaultManager.applySlash(0, 3e17); // 0.3 exchange rate

        // Verify the second slash overwrote the first
        StakingVaultManager.Batch memory batch = stakingVaultManager.getBatch(0);
        assertTrue(batch.slashed);
        assertEq(batch.slashedExchangeRate, 3e17);

        // Verify totalHypeProcessed was updated correctly
        assertEq(stakingVaultManager.totalHypeProcessed(), 30_000 * 1e18);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Helper Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to mock the core user exists check for a specific destination
    /// @param destination The destination address to check
    /// @param exists Whether the core user should exist on HyperCore
    function _mockCoreUserExists(address destination, bool exists) internal {
        L1ReadLibrary.CoreUserExists memory mockCoreUserExists = L1ReadLibrary.CoreUserExists({exists: exists});
        bytes memory encodedCoreUserExists = abi.encode(mockCoreUserExists);
        vm.mockCall(L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, abi.encode(destination), encodedCoreUserExists);
    }

    /// @dev Helper function to setup a user with vHYPE and queue a withdraw
    /// @param withdrawUser The user to setup
    /// @param vhypeAmount The amount of vHYPE to mint and queue for withdrawal
    /// @return withdrawId The ID of the queued withdraw
    function _setupWithdraw(address withdrawUser, uint256 vhypeAmount) internal returns (uint256 withdrawId) {
        // Transfer vHYPE to the user
        vm.prank(owner);
        vHYPE.transfer(withdrawUser, vhypeAmount);

        // User approves and queues withdraw
        vm.startPrank(withdrawUser);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        withdrawId = stakingVaultManager.queueWithdraw(vhypeAmount);
        vm.stopPrank();

        return withdrawId;
    }

    /// @dev Helper function to mock the calls that batch processing makes
    function _mockBatchProcessingCalls() internal {
        // Mock the calls that finalizeBatch makes
        vm.mockCall(address(stakingVault), abi.encodeWithSignature("transferHypeToCore(uint256)"), abi.encode());
        vm.mockCall(address(stakingVault), abi.encodeWithSignature("stake(address,uint64)"), abi.encode());
        vm.mockCall(address(stakingVault), abi.encodeWithSignature("unstake(address,uint64)"), abi.encode());
    }

    /// @dev Helper function to mock balances for testing exchange rate calculations
    /// @param totalBalance The total balance of HYPE to mock (in 18 decimals)
    /// @param totalSupply The total supply of vHYPE to mint to owner (in 18 decimals)
    function _mockBalancesForExchangeRate(uint256 totalBalance, uint256 totalSupply) internal {
        vm.assume(totalBalance.to8Decimals() <= type(uint64).max);

        uint64 delegatedBalance = totalBalance > 0 ? totalBalance.to8Decimals() : 0; // Convert to 8 decimals

        // Mock delegator summary and spot balance
        _mockDelegatorSummary(delegatedBalance);
        _mockSpotBalance(0); // Zero for simplicity

        // Mint vHYPE supply to owner
        if (totalSupply > 0) {
            vm.prank(address(stakingVaultManager));
            vHYPE.mint(owner, totalSupply);
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

    function _mockDelegations(uint64 weiAmount) internal {
        _mockDelegations(validator, weiAmount);
    }

    function _mockDelegations(address validator, uint64 weiAmount) internal {
        _mockDelegationsWithLock(validator, weiAmount, 0);
    }

    function _mockDelegationsWithLock(address validator, uint64 weiAmount, uint64 lockedUntilTimestamp) internal {
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](1);
        mockDelegations[0] = L1ReadLibrary.Delegation({
            validator: validator,
            amount: weiAmount,
            lockedUntilTimestamp: lockedUntilTimestamp
        });

        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);
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

    function _mockAndExpectTokenDelegateCall(address _validator, uint64 weiAmount, bool isUndelegate) internal {
        bytes memory encodedAction = abi.encode(_validator, weiAmount, isUndelegate);
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

    function _expectNoStakeCall() internal {
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);
    }

    function _expectNoUnstakeCall() internal {
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);
    }

    function _mockAndExpectSpotSendCall(address destination, uint64 tokenId, uint64 weiAmount) internal {
        bytes memory encodedAction = abi.encode(destination, tokenId, weiAmount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x06; // Spot send action ID
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

contract StakingVaultManagerWithExtraFunction is StakingVaultManager {
    constructor(uint64 _hypeTokenId) StakingVaultManager(_hypeTokenId) {}

    function extraFunction() public pure returns (bool) {
        return true;
    }
}

contract MockHypeSystemContract {
    using Converters for *;

    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address internal constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    uint64 public constant HYPE_TOKEN_ID = 150;

    receive() external payable {
        uint64 amount = msg.value.to8Decimals();

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
