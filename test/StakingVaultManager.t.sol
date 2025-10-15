// forge-lint: disable-start(mixed-case-variable)
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IStakingVaultManager} from "../src/interfaces/IStakingVaultManager.sol";
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
import {Converters} from "../src/libraries/Converters.sol";
import {IStakingVault} from "../src/interfaces/IStakingVault.sol";
import {HyperCoreSimulator} from "./HyperCoreSimulator.sol";
import {Constants} from "./mocks/Constants.sol";

contract StakingVaultManagerTest is Test, HyperCoreSimulator {
    using Converters for *;

    StakingVaultManager stakingVaultManager;
    RoleRegistry roleRegistry;
    VHYPE vHYPE;
    StakingVault stakingVault;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");

    address public validator = makeAddr("validator");
    address public validator2 = makeAddr("validator2");
    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID
    uint256 public constant MINIMUM_STAKE_BALANCE = 500_000 * 1e18; // 500k HYPE
    uint256 public constant MINIMUM_DEPOSIT_AMOUNT = 1e18; // 1 HYPE
    uint256 public constant MINIMUM_WITHDRAW_AMOUNT = 1e18; // 1 HYPE
    uint256 public constant MAXIMUM_WITHDRAW_AMOUNT = 10_000 * 1e18; // 10k HYPE

    // Events
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);
    event EmergencyStakingDeposit(address indexed sender, uint256 amount, string purpose);

    constructor() HyperCoreSimulator() {}

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
        address[] memory whitelistedValidators = new address[](2);
        whitelistedValidators[0] = validator;
        whitelistedValidators[1] = validator2;
        StakingVault stakingVaultImplementation = new StakingVault(HYPE_TOKEN_ID);
        bytes memory stakingVaultInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(roleRegistry), whitelistedValidators);
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        stakingVault = StakingVault(payable(stakingVaultProxy));

        // Deploy StakingVaultManager
        StakingVaultManager stakingVaultManagerImplementation = new StakingVaultManager();
        bytes memory stakingVaultManagerInitData = abi.encodeWithSelector(
            StakingVaultManager.initialize.selector,
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            validator,
            MINIMUM_STAKE_BALANCE,
            MINIMUM_DEPOSIT_AMOUNT,
            MINIMUM_WITHDRAW_AMOUNT,
            MAXIMUM_WITHDRAW_AMOUNT
        );
        ERC1967Proxy stakingVaultManagerProxy =
            new ERC1967Proxy(address(stakingVaultManagerImplementation), stakingVaultManagerInitData);
        stakingVaultManager = StakingVaultManager(payable(stakingVaultManagerProxy));

        // Setup roles
        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), address(stakingVaultManager));
        roleRegistry.grantRole(roleRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock the core user exists
        hl.mockCoreUserExists(address(stakingVault), true);
        hl.mockCoreUserExists(user, true);

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
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        stakingVaultManager.initialize(
            address(roleRegistry),
            address(vHYPE),
            address(stakingVault),
            validator,
            MINIMUM_STAKE_BALANCE,
            MINIMUM_DEPOSIT_AMOUNT,
            MINIMUM_WITHDRAW_AMOUNT,
            MAXIMUM_WITHDRAW_AMOUNT
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
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount);

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_VaultWithExistingStakeBalance() public withMinimumStakeBalance {
        uint256 depositAmount = 50_000 * 1e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount);

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateAboveOne() public withExchangeRate(500_000e18, 250_000e18) {
        uint256 depositAmount = 50_000e18; // 50k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 2:1 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount / 2);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount);

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExchangeRateBelowOne() public withExchangeRate(250_000e18, 500_000e18) {
        uint256 depositAmount = 100_000e18; // 100k HYPE

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: depositAmount}();

        // Check vHYPE was minted at 1:2 exchange rate
        uint256 userVHYPEBalance = vHYPE.balanceOf(user);
        assertEq(userVHYPEBalance, depositAmount * 2);
        assertEq(stakingVaultManager.vHYPEtoHYPE(userVHYPEBalance), depositAmount);

        // Check staking vault balance was updated
        assertEq(address(stakingVault).balance, depositAmount);

        // Check user's HYPE balance was deducted
        assertEq(user.balance, 0);
    }

    function test_Deposit_ExactMinimumAmount() public withMinimumStakeBalance {
        vm.deal(user, MINIMUM_DEPOSIT_AMOUNT);
        vm.prank(user);
        stakingVaultManager.deposit{value: MINIMUM_DEPOSIT_AMOUNT}();

        // vHYPE should be minted
        assertEq(vHYPE.balanceOf(user), MINIMUM_DEPOSIT_AMOUNT);

        // HYPE should be transferred to staking vault
        assertEq(address(stakingVault).balance, MINIMUM_DEPOSIT_AMOUNT);
    }

    function test_Deposit_BelowMinimumAmount() public withMinimumStakeBalance {
        uint256 belowMinimumAmount = MINIMUM_DEPOSIT_AMOUNT - 1; // 1 wei below minimum
        vm.deal(user, belowMinimumAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: belowMinimumAmount}();
    }

    function test_Deposit_ZeroAmount() public withMinimumStakeBalance {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: 0}();
    }

    function test_Deposit_RevertWhenContractPaused() public withMinimumStakeBalance {
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

    function test_Deposit_RevertsAfterFinalizeBatchWithDeposit() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // User does the first deposit
        vm.deal(user, vhypeAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: vhypeAmount}();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Next deposit should revert
        vm.deal(user, vhypeAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CannotReadSpotBalanceUntilNextBlock.selector));
        stakingVaultManager.deposit{value: vhypeAmount}();

        // Advance time by 1 block, should succeed
        warp(vm.getBlockTimestamp() + 1);
        stakingVaultManager.deposit{value: vhypeAmount}();
    }

    function test_Deposit_RevertsAfterClaimWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        warp(vm.getBlockTimestamp() + stakingVaultManager.claimWindowBuffer() + 7 days + 1);

        // Claim the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Deposit should revert
        vm.deal(user, vhypeAmount);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CannotReadSpotBalanceUntilNextBlock.selector));
        stakingVaultManager.deposit{value: vhypeAmount}();

        // Advance time by 1 block, should succeed
        warp(vm.getBlockTimestamp() + 1);
        stakingVaultManager.deposit{value: vhypeAmount}();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Queue Withdraw                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_QueueWithdraw_Success() public withMinimumStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // Setup: User has vHYPE balance
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        // Queue the withdraw
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);

        assertEq(withdrawIds.length, 1);
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 1);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).vhypeAmount, vhypeAmount);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).claimedAt, 0);

        // Verify vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount);
    }

    function test_QueueWithdraw_SplitIntoMultipleWithdraws() public withMinimumStakeBalance {
        uint256 vhypeAmount = 15_000 * 1e18; // 15k vHYPE

        // Setup: User has vHYPE balance
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        // Queue the withdraw
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);

        assertEq(withdrawIds.length, 2);
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 2);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).vhypeAmount, 10_000 * 1e18);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).claimedAt, 0);

        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).vhypeAmount, 5_000 * 1e18);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).claimedAt, 0);

        // Verify vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount);
    }

    function test_QueueWithdraw_SplitIntoMultipleWithdraws_TinyRemainder() public withMinimumStakeBalance {
        uint256 vhypeAmount = 20_000 * 1e18 + 1; // 20k vHYPE + 1 wei

        // Setup: User has vHYPE balance
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        // Queue the withdraw
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);

        assertEq(withdrawIds.length, 2);
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 2);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).vhypeAmount, 10_000 * 1e18);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[0]).claimedAt, 0);

        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).vhypeAmount, 10_000 * 1e18 + 1);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawIds[1]).claimedAt, 0);

        // Verify vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount);
    }

    function test_QueueWithdraw_ZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.ZeroAmount.selector);
        stakingVaultManager.queueWithdraw(0);
    }

    function test_QueueWithdraw_BelowMinimumAmount() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        vm.expectRevert(IStakingVaultManager.BelowMinimumWithdrawAmount.selector);
        stakingVaultManager.queueWithdraw(MINIMUM_WITHDRAW_AMOUNT - 1);
    }

    function test_QueueWithdraw_InsufficientBalance() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User doesn't have any vHYPE balance
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);

        vm.expectRevert();
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_InsufficientAllowance() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User has vHYPE balance but no allowance
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, vhypeAmount);

        // Queue the withdraw without approval
        vm.startPrank(user);
        vm.expectRevert();
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_MultipleWithdraws() public withMinimumStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 2_000 * 1e18; // 2k vHYPE
        uint256 totalVhype = vhypeAmount1 + vhypeAmount2;

        // Setup: User has vHYPE balance
        vm.prank(address(stakingVaultManager));
        vHYPE.mint(user, totalVhype);

        // User approves the staking vault manager to spend vHYPE
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), totalVhype);

        // Queue first withdraw
        uint256[] memory withdrawIds1 = stakingVaultManager.queueWithdraw(vhypeAmount1);
        assertEq(withdrawIds1.length, 1);
        uint256 withdrawId1 = withdrawIds1[0];

        // Queue second withdraw
        uint256[] memory withdrawIds2 = stakingVaultManager.queueWithdraw(vhypeAmount2);
        assertEq(withdrawIds2.length, 1);
        uint256 withdrawId2 = withdrawIds2[0];

        // Verify withdraw IDs are sequential
        assertEq(withdrawId1, 1);
        assertEq(withdrawId2, 2);

        // Verify withdraw queue length
        assertEq(stakingVaultManager.getWithdrawQueueLength(), 2);

        // Verify withdraw queue contents
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).vhypeAmount, vhypeAmount1);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawId1).claimedAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).vhypeAmount, vhypeAmount2);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).account, user);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).batchIndex, type(uint256).max);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).cancelledAt, 0);
        assertEq(stakingVaultManager.getWithdraw(withdrawId2).claimedAt, 0);

        // Verify all vHYPE was transferred to the staking vault manager
        assertEq(vHYPE.balanceOf(user), 0);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), totalVhype);
    }

    function test_QueueWithdraw_RevertsAfterFinalizeBatchWithDeposit() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        vm.deal(user, vhypeAmount);
        vm.startPrank(user);
        stakingVaultManager.deposit{value: vhypeAmount}();
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // User has vHYPE balance
        vm.startPrank(owner);
        vHYPE.transfer(user, vhypeAmount);

        // Try to queue withdraw when finalized
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CannotReadSpotBalanceUntilNextBlock.selector));
        stakingVaultManager.queueWithdraw(vhypeAmount);

        // Advance time by 1 block, should succeed
        warp(vm.getBlockTimestamp() + 1);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_RevertsAfterClaimWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        warp(vm.getBlockTimestamp() + stakingVaultManager.claimWindowBuffer() + 7 days + 1);

        // Claim the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // User has vHYPE balance
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        // Try to queue withdraw when finalized
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CannotReadSpotBalanceUntilNextBlock.selector));
        stakingVaultManager.queueWithdraw(vhypeAmount);

        // Advance time by 1 block, should succeed
        warp(vm.getBlockTimestamp() + 1);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        stakingVaultManager.queueWithdraw(vhypeAmount);
    }

    function test_QueueWithdraw_WhenContractPaused() public withMinimumStakeBalance {
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

    function test_ClaimWithdraw_Success() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimedAt > 0, "Withdraw should be marked as claimed");
        assertEq(stakingVaultManager.totalHypeClaimed(), vhypeAmount, "Total HYPE claimed should match withdraw amount");
        assertEq(
            stakingVaultManager.totalHypeProcessed(), vhypeAmount, "Total HYPE processed should match withdraw amount"
        );
    }

    function test_ClaimWithdraw_NotAuthorized() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        address otherUser = makeAddr("otherUser");

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Another user tries to claim the withdraw
        vm.prank(otherUser);
        vm.expectRevert(IStakingVaultManager.NotAuthorized.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WithdrawCancelled() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Setup: User cancels the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // User tries to claim the cancelled withdraw
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawCancelled.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_AlreadyClaimed() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // User tries to claim again
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawClaimed.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_TooEarly() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 6 days);

        // User tries to claim too early
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawUnclaimable.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_ExactlySevenDays() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days);

        // User tries to claim too early
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawUnclaimable.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_CoreUserDoesNotExist() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Core user does not exist
        address destination = makeAddr("destination");
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CoreUserDoesNotExist.selector, destination));
        stakingVaultManager.claimWithdraw(withdrawId, destination);
    }

    function test_ClaimWithdraw_InsufficientBalance() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock insufficient spot balance (only half of what's needed)
        hl.mockSpotBalance(address(stakingVault), HYPE_TOKEN_ID, (vhypeAmount / 2).to8Decimals());

        // User tries to claim but vault has insufficient balance
        vm.prank(user);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WhenContractPaused() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // User tries to claim when contract is paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.claimWithdraw(withdrawId, user);
    }

    function test_ClaimWithdraw_WithSlashedBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 5e17); // 0.5 exchange rate

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims the slashed withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimedAt > 0, "Withdraw should be marked as claimed");
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

    function test_ClaimWithdraw_ZeroAmountAfterConversion() public withExcessStakeBalance {
        // Use a very small vHYPE amount that rounds down to 0 in 8 decimals
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch to a very low exchange rate that results in 0 after 8 decimal conversion
        // Exchange rate that results in amount < 1e10 (which is 0 in 8 decimals)
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 1); // Extremely low exchange rate

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims the withdraw - should succeed even with 0 amount after conversion
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimedAt > 0, "Withdraw should be marked as claimed");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                Tests: Batch Claim Withdraws               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_BatchClaimWithdraws_Success() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE
        uint256 vhypeAmount3 = 2_000 * 1e18; // 2k vHYPE

        // Setup: User queues multiple withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);
        uint256 withdrawId3 = _setupWithdraw(user, vhypeAmount3);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraws claimable
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims all withdraws in batch
        uint256[] memory withdrawIds = new uint256[](3);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;
        withdrawIds[2] = withdrawId3;

        vm.prank(user);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);

        // Verify all withdraws were claimed
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(withdrawId1);
        StakingVaultManager.Withdraw memory withdraw2 = stakingVaultManager.getWithdraw(withdrawId2);
        StakingVaultManager.Withdraw memory withdraw3 = stakingVaultManager.getWithdraw(withdrawId3);
        assertTrue(withdraw1.claimedAt > 0, "Withdraw 1 should be marked as claimed");
        assertTrue(withdraw2.claimedAt > 0, "Withdraw 2 should be marked as claimed");
        assertTrue(withdraw3.claimedAt > 0, "Withdraw 3 should be marked as claimed");

        uint256 totalVhype = vhypeAmount1 + vhypeAmount2 + vhypeAmount3;
        assertEq(stakingVaultManager.totalHypeClaimed(), totalVhype, "Total HYPE claimed should match sum of withdraws");
        assertEq(
            stakingVaultManager.totalHypeProcessed(), totalVhype, "Total HYPE processed should match sum of withdraws"
        );
    }

    function test_BatchClaimWithdraws_SingleWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a single withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims single withdraw using batch function
        uint256[] memory withdrawIds = new uint256[](1);
        withdrawIds[0] = withdrawId;

        vm.prank(user);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);

        // Verify the withdraw was claimed
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertTrue(withdraw.claimedAt > 0, "Withdraw should be marked as claimed");
        assertEq(stakingVaultManager.totalHypeClaimed(), vhypeAmount, "Total HYPE claimed should match withdraw amount");
    }

    function test_BatchClaimWithdraws_EmptyArray() public withExcessStakeBalance {
        // User tries to claim with empty array
        uint256[] memory withdrawIds = new uint256[](0);

        vm.prank(user);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_OneNotAuthorized() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE
        address otherUser = makeAddr("otherUser");

        // Setup: Two users queue withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(otherUser, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User tries to claim both withdraws (including one they don't own)
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.NotAuthorized.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_OneCancelled() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Cancel the second withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId2);

        // Process and finalize the batch (only first withdraw should be included)
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User tries to claim both withdraws
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawCancelled.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_OneUnprocessed() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);

        // Process and finalize the batch (only first withdraw)
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Queue another withdraw after batch is finalized
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User tries to claim both withdraws
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawNotProcessed.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_OneAlreadyClaimed() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims first withdraw individually
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId1, user);

        // User tries to claim both withdraws in batch
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawClaimed.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_OneTooEarly() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues first withdraw
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);

        // Process and finalize the first batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
        uint256 firstBatchFinalizedAt = vm.getBlockTimestamp();

        // Fast-forward time past the 1-day delay for next batch
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // Queue second withdraw
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the second batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make only first withdraw claimable
        // Set time to 7 days + buffer + 1 second after first batch, but not enough for second batch
        warp(firstBatchFinalizedAt + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User tries to claim both withdraws
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawUnclaimable.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_WithSlashedBatch() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 5e17); // 0.5 exchange rate

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims both slashed withdraws
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);

        // Verify both withdraws were claimed with slashed amounts
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(withdrawId1);
        StakingVaultManager.Withdraw memory withdraw2 = stakingVaultManager.getWithdraw(withdrawId2);
        assertTrue(withdraw1.claimedAt > 0, "Withdraw 1 should be marked as claimed");
        assertTrue(withdraw2.claimedAt > 0, "Withdraw 2 should be marked as claimed");

        uint256 totalVhype = vhypeAmount1 + vhypeAmount2;
        assertEq(
            stakingVaultManager.totalHypeClaimed(),
            totalVhype / 2,
            "Total HYPE claimed should match slashed withdraw amounts"
        );
    }

    function test_BatchClaimWithdraws_ZeroAmountAfterConversion() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch to a very low exchange rate that results in 0 after 8 decimal conversion
        // Exchange rate that results in amount < 1e10 (which is 0 in 8 decimals)
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 1); // Extremely low exchange rate

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims both withdraws - should succeed even with 0 total amount after conversion
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);

        // Verify both withdraws were claimed
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(withdrawId1);
        StakingVaultManager.Withdraw memory withdraw2 = stakingVaultManager.getWithdraw(withdrawId2);
        assertTrue(withdraw1.claimedAt > 0, "Withdraw 1 should be marked as claimed");
        assertTrue(withdraw2.claimedAt > 0, "Withdraw 2 should be marked as claimed");
    }

    function test_BatchClaimWithdraws_WhenContractPaused() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // User tries to claim when contract is paused
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_CoreUserDoesNotExist() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Core user does not exist
        address destination = makeAddr("destination");
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CoreUserDoesNotExist.selector, destination));
        stakingVaultManager.batchClaimWithdraws(withdrawIds, destination);
    }

    function test_BatchClaimWithdraws_InsufficientBalance() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE

        // Setup: User queues two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Mock insufficient spot balance (only half of what's needed)
        uint256 totalVhype = vhypeAmount1 + vhypeAmount2;
        hl.mockSpotBalance(address(stakingVault), HYPE_TOKEN_ID, (totalVhype / 2).to8Decimals());

        // User tries to claim but vault has insufficient balance
        uint256[] memory withdrawIds = new uint256[](2);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;

        vm.prank(user);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);
    }

    function test_BatchClaimWithdraws_MixedBatches() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE
        uint256 vhypeAmount3 = 2_000 * 1e18; // 2k vHYPE

        // Setup: User queues first two withdraws
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process and finalize the first batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time past the 1-day delay for next batch
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // Queue third withdraw
        uint256 withdrawId3 = _setupWithdraw(user, vhypeAmount3);

        // Process and finalize the second batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make all withdraws claimable
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // User claims all withdraws from both batches
        uint256[] memory withdrawIds = new uint256[](3);
        withdrawIds[0] = withdrawId1;
        withdrawIds[1] = withdrawId2;
        withdrawIds[2] = withdrawId3;

        vm.prank(user);
        stakingVaultManager.batchClaimWithdraws(withdrawIds, user);

        // Verify all withdraws were claimed
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(withdrawId1);
        StakingVaultManager.Withdraw memory withdraw2 = stakingVaultManager.getWithdraw(withdrawId2);
        StakingVaultManager.Withdraw memory withdraw3 = stakingVaultManager.getWithdraw(withdrawId3);
        assertTrue(withdraw1.claimedAt > 0, "Withdraw 1 should be marked as claimed");
        assertTrue(withdraw2.claimedAt > 0, "Withdraw 2 should be marked as claimed");
        assertTrue(withdraw3.claimedAt > 0, "Withdraw 3 should be marked as claimed");

        uint256 totalVhype = vhypeAmount1 + vhypeAmount2 + vhypeAmount3;
        assertEq(stakingVaultManager.totalHypeClaimed(), totalVhype, "Total HYPE claimed should match sum of withdraws");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Cancel Withdraw                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_CancelWithdraw_Success() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

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
        assertTrue(withdraw.cancelledAt > 0, "Withdraw should be marked as cancelled");

        // Verify vHYPE was refunded
        assertEq(vHYPE.balanceOf(user), vhypeAmount, "User should receive vHYPE refund");
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), 0, "Contract should have no vHYPE");
    }

    function test_CancelWithdraw_NotAuthorized() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        address otherUser = makeAddr("otherUser");

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Another user tries to cancel the withdraw
        vm.prank(otherUser);
        vm.expectRevert(IStakingVaultManager.NotAuthorized.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_AlreadyCancelled() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // User cancels the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // User tries to cancel again
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawCancelled.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_AlreadyProcessed() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify the withdraw was processed
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Withdraw should be processed");

        // User tries to cancel the processed withdraw
        vm.prank(user);
        vm.expectRevert(IStakingVaultManager.WithdrawProcessed.selector);
        stakingVaultManager.cancelWithdraw(withdrawId);
    }

    function test_CancelWithdraw_WhenContractPaused() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

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

    function test_ProcessBatch_FirstBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 10_000 * 1e18; // 10k vHYPE
        uint256 totalSupply = vHYPE.totalSupply();

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
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not change until batch is finalized");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Last processed withdraw ID should be 1");
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw.vhypeAmount, vhypeAmount, "Withdraw has incorrect amount of vHYPE");
        assertEq(withdraw.batchIndex, 0, "Withdraw has incorrect batch index");
        assertEq(withdraw.claimedAt, 0, "Withdraw should not have been claimed");

        // Verify vHYPE state
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount, "vHYPE should still be in escrow");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
        assertEq(stakingVaultManager.totalHypeClaimed(), 0, "Total HYPE claimed should be 0");
    }

    function test_ProcessBatch_UnderMinimumStakeBalance() public underMinimumStakeBalance {
        uint256 vhypeAmount = 10_000 * 1e18; // 10k vHYPE
        uint256 totalSupply = vHYPE.totalSupply();

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
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not change until batch is finalized");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw.vhypeAmount, vhypeAmount, "Withdraw has incorrect amount of vHYPE");
        assertEq(withdraw.batchIndex, type(uint256).max, "Withdraw should not have been assigned to a batch");
        assertEq(withdraw.claimedAt, 0, "Withdraw should not have been claimed");

        // Verify vHYPE state
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), vhypeAmount, "vHYPE should still be in escrow");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
        assertEq(stakingVaultManager.totalHypeClaimed(), 0, "Total HYPE claimed should be 0");
    }

    function test_ProcessBatch_WithOneDayLockedStake() public withExcessStakeBalance {
        uint256 vhypeAmount = 10_000 * 1e18; // 10k vHYPE

        _mockDelegationsWithLock(
            validator, vHYPE.totalSupply().to8Decimals(), uint64((vm.getBlockTimestamp() + 1 days) * 1000)
        );

        // User queues the first withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Process the first batch (should work without timing restrictions)
        warp(vm.getBlockTimestamp() + 1 days + 1 seconds);
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the first batch
        stakingVaultManager.finalizeBatch();

        // User queues the second withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Try to process immediately (should fail due to timing restriction)
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVaultManager.BatchNotReady.selector, vm.getBlockTimestamp() + 1 days)
        );
        stakingVaultManager.processBatch(type(uint256).max);

        // Advance time by 1 day + 1 second and try again (should succeed)
        warp(vm.getBlockTimestamp() + 1 days + 1 seconds);
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

    function test_ProcessBatch_WithOneDayLockedStakeAndExtraTime() public withExcessStakeBalance {
        uint256 vhypeAmount = 10_000 * 1e18; // 10k vHYPE

        // User queues the first withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Process the first batch (should work without timing restrictions)
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the first batch
        stakingVaultManager.finalizeBatch();

        // Advance time by 1 day + 1 second
        uint256 lockTime = vm.getBlockTimestamp() + 1 days + 1 seconds;
        warp(lockTime);

        // Simulate a delay in the 1-day stake lock
        // forge-lint: disable-next-line(unsafe-typecast)
        _mockDelegationsWithLock(validator, vHYPE.totalSupply().to8Decimals(), uint64(lockTime * 1000));

        // User queues the second withdraw
        _setupWithdraw(user, vhypeAmount / 2);

        // Should fail because the batch is not ready
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.BatchNotReady.selector, lockTime));
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_RevertsAfterClaimWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        warp(vm.getBlockTimestamp() + stakingVaultManager.claimWindowBuffer() + 7 days + 1);

        // Claim the withdraw
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        // Try to process batch when finalized
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CannotReadSpotBalanceUntilNextBlock.selector));
        stakingVaultManager.processBatch(type(uint256).max);

        // Advance time by 1 second, should succeed
        warp(vm.getBlockTimestamp() + 1);
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_WhenBatchProcessingPaused() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: Set batch processing to paused
        vm.prank(owner);
        stakingVaultManager.setBatchProcessingPaused(true);

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Batch processing is paused by default, so this should fail
        vm.expectRevert(IStakingVaultManager.BatchProcessingPaused.selector);
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_WhenContractPaused() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Pause the entire contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVaultManager));

        // Try to process batch when contract is paused
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVaultManager)));
        stakingVaultManager.processBatch(type(uint256).max);
    }

    function test_ProcessBatch_InsufficientCapacity() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE (more than available capacity)

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

    function test_ProcessBatch_PartialProcessing() public withExcessStakeBalanceAmount(10_000 * 1e18) {
        uint256 totalSupply = vHYPE.totalSupply();
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 10_000 * 1e18; // 10k vHYPE (this one won't fit)
        address user2 = makeAddr("user2");

        // Setup: Two users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user2, vhypeAmount2);

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
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not change until batch is finalized");
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

    function test_ProcessBatch_EmptyQueue() public withExcessStakeBalance {
        uint256 totalSupply = vHYPE.totalSupply();

        // Process batch with no withdraws in queue
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify batch state
        assertEq(stakingVaultManager.getBatchesLength(), 1, "Batch length should be 1");
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, 0, "Batch should have processed 0 vHYPE");
        assertEq(stakingVaultManager.getBatch(0).finalizedAt, 0, "Batch should not be finalized yet");

        // Verify withdraw state
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");

        // Verify vHYPE state
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not have changed");

        // Verify process state
        assertEq(stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0");
    }

    function test_ProcessBatch_CancelledWithdrawsSkipped() public withExcessStakeBalance {
        uint256 totalSupply = vHYPE.totalSupply();
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 7_000 * 1e18; // 7k vHYPE
        address user2 = makeAddr("user2");

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
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not change until batch is finalized");

        // Verify process state
        assertEq(
            stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0 until batch is finalized"
        );
    }

    function test_ProcessBatch_MultipleWithdraws() public withExcessStakeBalance {
        uint256 totalSupply = vHYPE.totalSupply();
        uint256 vhypeAmount1 = 2_000 * 1e18; // 2k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE
        uint256 vhypeAmount3 = 4_000 * 1e18; // 4k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

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
        assertEq(vHYPE.totalSupply(), totalSupply, "vHYPE supply should not change until batch is finalized");
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

    function test_ProcessBatch_ReturnValue_ProcessesAllWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 2_000 * 1e18; // 2k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 3k vHYPE
        uint256 vhypeAmount3 = 4_000 * 1e18; // 4k vHYPE

        // Setup: Three users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user, vhypeAmount2);
        _setupWithdraw(user, vhypeAmount3);

        // Process batch with max uint256 (process all)
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);

        // Should process all 3 withdrawals
        assertEq(numProcessed, 3, "Should have processed 3 withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Last processed withdraw ID should be 3");
    }

    function test_ProcessBatch_ReturnValue_LimitedWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // Setup: Queue 5 withdraws
        for (uint256 i = 0; i < 5; i++) {
            _setupWithdraw(user, vhypeAmount);
        }

        // Process batch with limit of 3
        uint256 numProcessed = stakingVaultManager.processBatch(3);

        // Should process exactly 3 withdrawals
        assertEq(numProcessed, 3, "Should have processed 3 withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Last processed withdraw ID should be 3");

        // Process the remaining withdrawals
        uint256 numProcessed2 = stakingVaultManager.processBatch(type(uint256).max);

        // Should process the remaining 2 withdrawals
        assertEq(numProcessed2, 2, "Should have processed 2 more withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 5, "Last processed withdraw ID should be 5");
    }

    function test_ProcessBatch_ReturnValue_EmptyQueue() public withExcessStakeBalance {
        // Process batch with empty queue
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);

        // Should process 0 withdrawals
        assertEq(numProcessed, 0, "Should have processed 0 withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
    }

    function test_ProcessBatch_ReturnValue_InsufficientCapacity() public withMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE (more than available capacity)

        // Setup: User queues a large withdraw that exceeds capacity
        _setupWithdraw(user, vhypeAmount);

        // Process batch (should process 0 withdraws due to insufficient capacity)
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);

        // Should process 0 withdrawals
        assertEq(numProcessed, 0, "Should have processed 0 withdrawals due to insufficient capacity");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
    }

    function test_ProcessBatch_ReturnValue_PartialCapacity() public withExcessStakeBalanceAmount(10_000 * 1e18) {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 10_000 * 1e18; // 10k vHYPE (this one won't fit)

        // Setup: Two users queue withdraws
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user, vhypeAmount2);

        // Process batch (should only process first withdraw due to capacity)
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);

        // Should process only 1 withdrawal
        assertEq(numProcessed, 1, "Should have processed only 1 withdrawal due to capacity limits");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 1, "Last processed withdraw ID should be 1");
    }

    function test_ProcessBatch_ReturnValue_WithCancelledWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: Queue 3 withdraws
        _setupWithdraw(user, vhypeAmount);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount);
        _setupWithdraw(user, vhypeAmount);

        // Cancel the second withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId2);

        // Process batch
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);

        // Should process all 2 withdrawals (not including the cancelled one)
        assertEq(numProcessed, 2, "Should have processed 2 withdrawals (excluding cancelled)");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Last processed withdraw ID should be 3");

        // But batch should only have 2 withdrawals worth of vHYPE (cancelled one is skipped)
        assertEq(
            stakingVaultManager.getBatch(0).vhypeProcessed,
            vhypeAmount * 2,
            "Batch should have processed 10k vHYPE (2 withdraws)"
        );
    }

    function test_ProcessBatch_ReturnValue_ZeroWithdrawalsRequested() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: Queue some withdraws
        _setupWithdraw(user, vhypeAmount);
        _setupWithdraw(user, vhypeAmount);

        // Process batch with 0 withdrawals
        uint256 numProcessed = stakingVaultManager.processBatch(0);

        // Should process 0 withdrawals
        assertEq(numProcessed, 0, "Should have processed 0 withdrawals when limit is 0");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
    }

    function test_ProcessBatch_ReturnValue_MultipleCallsInSameBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // Setup: Queue 6 withdraws
        for (uint256 i = 0; i < 6; i++) {
            _setupWithdraw(user, vhypeAmount);
        }

        // First call: process 2 withdrawals
        uint256 numProcessed1 = stakingVaultManager.processBatch(2);
        assertEq(numProcessed1, 2, "First call should process 2 withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 2, "Last processed should be 2");

        // Second call: process 3 more withdrawals
        uint256 numProcessed2 = stakingVaultManager.processBatch(3);
        assertEq(numProcessed2, 3, "Second call should process 3 withdrawals");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 5, "Last processed should be 5");

        // Third call: process remaining withdrawals
        uint256 numProcessed3 = stakingVaultManager.processBatch(type(uint256).max);
        assertEq(numProcessed3, 1, "Third call should process 1 withdrawal");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 6, "Last processed should be 6");

        // Verify total in batch
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, vhypeAmount * 6, "Batch should have all 6 withdrawals");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Finalize Batch                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_FinalizeBatch_CanFinalizeWhenUnderMinimumStakeBalance() public underMinimumStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE withdraw

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Verify state
        assertEq(stakingVaultManager.totalHypeProcessed(), 0, "Total HYPE processed should be 0");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "Last processed withdraw ID should be 0");
    }

    function test_FinalizeBatch_DustHypeAmountNotTransferred() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        uint256 hypeDeposits = 5_000 * 1e18; // 5k HYPE deposits (exchange rate = 1)
        uint256 dustHypeAmount = 0.5e10; // dust
        address user2 = makeAddr("user2");

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits + dustHypeAmount);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits + dustHypeAmount}();

        // Expect a transfer to HyperCore call with the dust amount removed
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsEqualWithdraws() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        uint256 hypeDeposits = 5_000 * 1e18; // 5k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Only expect a transfer to HyperCore call
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsGreaterThanWithdraws() public withMinimumStakeBalance {
        uint256 vhypeAmount = 3_000 * 1e18; // 3k vHYPE withdraw
        uint256 hypeDeposits = 5_000 * 1e18; // 5k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Mock and expect calls for deposits > withdraws scenario

        // First call: transfer all deposits to HyperCore
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode((hypeDeposits - vhypeAmount).to8Decimals()));
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE,
            abi.encode(
                validator,
                (hypeDeposits - vhypeAmount).to8Decimals(),
                false /* isUndelegate */
            )
        );

        // No undelegate call or staking withdraw call expected
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_DepositsLessThanWithdraws() public withExcessStakeBalance {
        uint256 vhypeAmount = 70_000 * 1e18; // 70k vHYPE withdraw
        uint256 hypeDeposits = 30_000 * 1e18; // 30k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // Setup: User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Mock and expect calls for deposits < withdraws scenario

        // First call: transfer all deposits to core
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());

        // Second call: undelegate shortfall amount (use CoreWriter helper)
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE,
            abi.encode(
                validator,
                (vhypeAmount - hypeDeposits).to8Decimals(),
                true /* isUndelegate */
            )
        );

        // Third call: withdraw shortfall from staking (use CoreWriter helper)
        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode((vhypeAmount - hypeDeposits).to8Decimals()));

        // No staking deposit or delegate call expected
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CanFinalizeWithRemainingWithdraws() public withExcessStakeBalance {
        // Setup: User queues a withdraw
        _setupWithdraw(user, 5_000 * 1e18);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Queue another withdraw
        _setupWithdraw(user, 5_000 * 1e18);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Verify state
        assertEq(stakingVaultManager.totalHypeProcessed(), 10_000 * 1e18, "Total HYPE processed should be 10k");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 2, "Last processed withdraw ID should be 2");
    }

    function test_FinalizeBatch_StakesExcessAfterSlash() public withExcessStakeBalance {
        uint256 originalBalance = vHYPE.totalSupply();
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        //
        // Total: 600k
        // Delegated: 500k
        // Pending withdrawal: 100k
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // 50% slash, but only on the delegated amount
        //
        // Total: 300k
        // Delegated: 200k
        // Pending withdrawal: 100k
        L1ReadLibrary.DelegatorSummary memory originalDelegatorSummary = stakingVault.delegatorSummary();
        L1ReadLibrary.DelegatorSummary memory slashedDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 0, // Added in the next mockDelegation call
            undelegated: 0,
            totalPendingWithdrawal: originalDelegatorSummary.totalPendingWithdrawal,
            nPendingWithdrawals: originalDelegatorSummary.nPendingWithdrawals
        });
        hl.mockDelegatorSummary(address(stakingVault), slashedDelegatorSummary);
        uint64 remainingDelegatedAmount =
            (originalBalance.to8Decimals() / 2) - originalDelegatorSummary.totalPendingWithdrawal;
        hl.mockDelegation(
            address(stakingVault),
            L1ReadLibrary.Delegation({
                validator: validator,
                amount: remainingDelegatedAmount,
                lockedUntilTimestamp: uint64(vm.getBlockTimestamp() * 1000)
            })
        );

        // Slash the batch to 0.5 exchange rate (50% of original)
        uint256 slashedExchangeRate = 0.5e18;
        vm.prank(owner);
        stakingVaultManager.applySlash(0, slashedExchangeRate);

        // Only expect one staking deposit call at the very end
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode(50_000 * 1e8), 1);

        // Fast foward one day. We have 50k excess, but it's in pending, so we
        // don't expect any staking deposit calls.
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // Process and finalize
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Check that nothing changed
        L1ReadLibrary.DelegatorSummary memory newDelegatorSummary = stakingVault.delegatorSummary();
        assertEq(newDelegatorSummary.delegated, remainingDelegatedAmount);
        assertEq(newDelegatorSummary.undelegated, slashedDelegatorSummary.undelegated);
        assertEq(newDelegatorSummary.totalPendingWithdrawal, slashedDelegatorSummary.totalPendingWithdrawal);
        assertEq(newDelegatorSummary.nPendingWithdrawals, slashedDelegatorSummary.nPendingWithdrawals);

        // Now fast forward five days. The 50k excess should now be in spot,
        // so we expect a staking deposit call.
        warp(vm.getBlockTimestamp() + 5 days + 1);

        // Process and finalize
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_WithdrawsExcessAfterSlash() public withExcessStakeBalance {
        uint64 startTimestamp = uint64(vm.getBlockTimestamp() * 1000);
        uint256 originalBalance = vHYPE.totalSupply();
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        //
        // Total: 600k
        // Delegated: 500k
        // Pending withdrawal: 100k
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
        warp(startTimestamp + 1 days + 1);

        // 50% slash, all from pending withdrawal
        //
        // Total: 300k
        // Delegated: 300k
        // Pending withdrawal: 0k
        hl.mockDelegatorSummary(
            address(stakingVault),
            L1ReadLibrary.DelegatorSummary({
                delegated: 0, // Added in the next mockDelegation call
                undelegated: 0,
                totalPendingWithdrawal: 0,
                nPendingWithdrawals: 0
            })
        );
        hl.mockDelegation(
            address(stakingVault),
            L1ReadLibrary.Delegation({
                validator: validator, amount: originalBalance.to8Decimals() / 2, lockedUntilTimestamp: startTimestamp
            })
        );

        // Slash the batch to 0.5 exchange rate (50% of original)
        uint256 slashedExchangeRate = 0.5e18;
        vm.prank(owner);
        stakingVaultManager.applySlash(0, slashedExchangeRate);

        // We need 50k HYPE to cover withdraws, but we don't have any. So we expect a withdraw from staking.
        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode(50_000 * 1e8));

        // Finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterSwitchValidatorInSameBlock() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Switch validator
        vm.prank(owner);
        stakingVaultManager.switchValidator(validator2);

        // Finalize the batch
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterEmergencyStakingWithdrawInSameBlock() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Emergency withdraw
        vm.startPrank(owner);
        stakingVaultManager.emergencyStakingWithdraw(vHYPE.totalSupply(), "Emergency withdraw");

        // Finalize the batch
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CannotFinalizeAfterSlash() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        uint256 hypeDeposits = 5_000 * 1e18; // 5k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // User 1 queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Apply slash to the batch (50% slash)
        _mockDelegations(validator, (vHYPE.totalSupply() / 2).to8Decimals());

        // Attempt to finalize should revert due to insufficient balance
        vm.expectRevert(IStakingVaultManager.NotEnoughBalance.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_CanFinalizeAfterSlashIsApplied() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE
        uint256 hypeDeposits = 5_000 * 1e18; // 5k HYPE deposits (exchange rate = 1)
        address user2 = makeAddr("user2");

        // User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // User 2 deposits HYPE into the vault
        vm.deal(user2, hypeDeposits);
        vm.prank(user2);
        stakingVaultManager.deposit{value: hypeDeposits}();

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Apply slash to the batch (50% slash)
        _mockDelegations(validator, (vHYPE.totalSupply() / 2).to8Decimals());

        // Reset the batch
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Process the batch again
        stakingVaultManager.processBatch(type(uint256).max);

        // Mock and expect calls for for the deposit
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode(hypeDeposits.to8Decimals()));
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE,
            abi.encode(
                validator,
                hypeDeposits.to8Decimals(),
                false /* isUndelegate */
            )
        );

        // Finalize the batch
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_MaxPendingWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE withdraw

        for (uint256 i = 0; i < 5; i++) {
            _setupWithdraw(user, vhypeAmount);
            stakingVaultManager.processBatch(type(uint256).max);
            stakingVaultManager.finalizeBatch();
            warp(vm.getBlockTimestamp() + 1 days + 1 seconds);
        }

        _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Should revert due to max pending withdrawals
        vm.expectRevert(IStakingVault.MaxPendingWithdrawals.selector);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_ZeroWithdraws() public withMinimumStakeBalance {
        uint256 hypeDeposits = 50_000 * 1e18; // 50k HYPE deposits

        // Setup: Mock vault balance with deposits but no withdraws
        vm.deal(address(stakingVault), hypeDeposits);

        // Mock and expect calls for zero withdraws scenario

        // First call: transfer all deposits to core
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), hypeDeposits, abi.encode());

        // Second call: stake all deposits
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode(hypeDeposits.to8Decimals()));

        // Third call: delegate all deposits
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE,
            abi.encode(
                validator,
                hypeDeposits.to8Decimals(),
                false /* isUndelegate */
            )
        );

        // No undelegate call or staking withdraw call expected
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    function test_FinalizeBatch_ZeroDepositsZeroWithdraws() public withMinimumStakeBalance {
        // No HyperCore deposit expected
        vm.expectCall(address(Constants.HYPE_SYSTEM_ADDRESS), abi.encode(), 0);

        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.stake.selector), 0);
        vm.expectCall(address(stakingVault), abi.encodeWithSelector(StakingVault.unstake.selector), 0);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: Get Withdraw Amount and Claimable At       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GetWithdrawAmount_UnprocessedWithdraw() public withExchangeRate(600_000e18, 400_000e18) {
        // Mock exchange rate = 1.5 (150% - vault has earned 50% yield)
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // Queue a withdraw (not processed yet)
        _setupWithdraw(user, vhypeAmount);

        // Get withdraw amount - should use current exchange rate
        uint256 withdrawAmount = stakingVaultManager.getWithdrawAmount(1);

        assertEq(withdrawAmount, 3_000 * 1e18);
    }

    function test_GetWithdrawAmount_ProcessedWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Queue and process withdraw
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify withdraw is in batch 0
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(1);
        assertEq(withdraw.batchIndex, 0);

        // Get withdraw amount - should use snapshot exchange rate from batch
        uint256 withdrawAmount = stakingVaultManager.getWithdrawAmount(1);

        assertEq(withdrawAmount, vhypeAmount);
    }

    function test_GetWithdrawAmount_SlashedBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Queue and process withdraw
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Slash the batch to 0.8 exchange rate (80% of original)
        uint256 slashedExchangeRate = 0.8e18;
        vm.prank(owner);
        stakingVaultManager.applySlash(0, slashedExchangeRate);

        // Get withdraw amount - should use slashed exchange rate
        uint256 withdrawAmount = stakingVaultManager.getWithdrawAmount(1);

        // Expected: 5k vHYPE * 0.8 = 4k HYPE (using slashed rate)
        assertEq(withdrawAmount, 4_000 * 1e18);
    }

    function test_GetWithdrawAmount_CancelledWithdraw() public withMinimumStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Queue a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Cancel the withdraw
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId);

        // Get withdraw amount - should return 0 for cancelled withdraw
        uint256 withdrawAmount = stakingVaultManager.getWithdrawAmount(withdrawId);

        assertEq(withdrawAmount, 0, "Cancelled withdraw should return 0 amount");

        // Verify the withdraw is actually cancelled
        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawId);
        assertGt(withdraw.cancelledAt, 0, "Withdraw should have cancelledAt timestamp");
    }

    function test_GetWithdrawClaimableAt_UnprocessedWithdraw() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Queue a withdraw (not processed yet)
        _setupWithdraw(user, vhypeAmount);

        // Should return max uint256 for unprocessed withdraw
        uint256 claimableAt = stakingVaultManager.getWithdrawClaimableAt(1);
        assertEq(claimableAt, type(uint256).max);
    }

    function test_GetWithdrawClaimableAt_NotFinalized() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18;

        // Queue and process withdraw (but don't finalize)
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Should return max uint256 for processed but not finalized
        uint256 claimableAt = stakingVaultManager.getWithdrawClaimableAt(1);
        assertEq(claimableAt, type(uint256).max);
    }

    function test_GetWithdrawClaimableAt_Finalized() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18;

        // Queue, process, and finalize withdraw
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        uint256 finalizeTime = vm.getBlockTimestamp();
        stakingVaultManager.finalizeBatch();

        // Get claimable time
        uint256 claimableAt = stakingVaultManager.getWithdrawClaimableAt(1);

        // Expected: finalize time + 7 days + claim window buffer (1 day default)
        uint256 expectedClaimableAt = finalizeTime + 7 days + stakingVaultManager.claimWindowBuffer();
        assertEq(claimableAt, expectedClaimableAt);
    }

    function test_GetWithdrawClaimableAt_WithCustomClaimWindowBuffer() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18;
        uint256 customBuffer = 3 days;

        // Set custom claim window buffer
        vm.prank(owner);
        stakingVaultManager.setClaimWindowBuffer(customBuffer);

        // Queue, process, and finalize withdraw
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        uint256 finalizeTime = vm.getBlockTimestamp();
        stakingVaultManager.finalizeBatch();

        // Get claimable time
        uint256 claimableAt = stakingVaultManager.getWithdrawClaimableAt(1);

        // Expected: finalize time + 7 days + custom buffer (3 days)
        uint256 expectedClaimableAt = finalizeTime + 7 days + customBuffer;
        assertEq(claimableAt, expectedClaimableAt);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               Tests: Get Account Withdraws                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GetAccountWithdraws_NoWithdrawals() public {
        // Query withdrawals for an account that has never withdrawn
        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        assertEq(withdraws.length, 0, "Account with no withdrawals should return empty array");
    }

    function test_GetAccountWithdraws_SingleWithdrawal() public withMinimumStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18;

        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        assertEq(withdraws.length, 1, "Should return 1 withdrawal");
        assertEq(withdraws[0].id, withdrawId, "Withdrawal ID should match");
        assertEq(withdraws[0].account, user, "Account should match");
        assertEq(withdraws[0].vhypeAmount, vhypeAmount, "vHYPE amount should match");
    }

    function test_GetAccountWithdraws_MultipleWithdrawals() public withMinimumStakeBalance {
        uint256 vhypeAmount1 = 2_000 * 1e18;
        uint256 vhypeAmount2 = 3_000 * 1e18;
        uint256 vhypeAmount3 = 1_500 * 1e18;

        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);
        uint256 withdrawId3 = _setupWithdraw(user, vhypeAmount3);

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        assertEq(withdraws.length, 3, "Should return 3 withdrawals");
        assertEq(withdraws[0].id, withdrawId1, "First withdrawal ID should match");
        assertEq(withdraws[1].id, withdrawId2, "Second withdrawal ID should match");
        assertEq(withdraws[2].id, withdrawId3, "Third withdrawal ID should match");
        assertEq(withdraws[0].vhypeAmount, vhypeAmount1, "First withdrawal amount should match");
        assertEq(withdraws[1].vhypeAmount, vhypeAmount2, "Second withdrawal amount should match");
        assertEq(withdraws[2].vhypeAmount, vhypeAmount3, "Third withdrawal amount should match");
    }

    function test_GetAccountWithdraws_WithCancelledWithdrawal() public withMinimumStakeBalance {
        uint256 vhypeAmount1 = 2_000 * 1e18;
        uint256 vhypeAmount2 = 3_000 * 1e18;

        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Cancel the first withdrawal
        vm.prank(user);
        stakingVaultManager.cancelWithdraw(withdrawId1);

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        // Should still return both withdrawals, but first one will have cancelledAt timestamp
        assertEq(withdraws.length, 2, "Should return 2 withdrawals (including cancelled)");
        assertEq(withdraws[0].id, withdrawId1, "First withdrawal ID should match");
        assertEq(withdraws[1].id, withdrawId2, "Second withdrawal ID should match");
        assertGt(withdraws[0].cancelledAt, 0, "First withdrawal should be cancelled");
        assertEq(withdraws[1].cancelledAt, 0, "Second withdrawal should not be cancelled");
    }

    function test_GetAccountWithdraws_WithProcessedWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 2_000 * 1e18;
        uint256 vhypeAmount2 = 3_000 * 1e18;

        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // Process both withdrawals
        stakingVaultManager.processBatch(type(uint256).max);

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        assertEq(withdraws.length, 2, "Should return 2 withdrawals");
        assertEq(withdraws[0].batchIndex, 0, "First withdrawal should be in batch 0");
        assertEq(withdraws[1].batchIndex, 0, "Second withdrawal should be in batch 0");
    }

    function test_GetAccountWithdraws_WithClaimedWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18;

        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Warp past the claim window
        warp(vm.getBlockTimestamp() + 7 days + 12 hours + 1 seconds);

        // Claim the withdrawal
        vm.prank(user);
        stakingVaultManager.claimWithdraw(withdrawId, user);

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        assertEq(withdraws.length, 1, "Should return 1 withdrawal");
        assertEq(withdraws[0].id, withdrawId, "Withdrawal ID should match");
        assertGt(withdraws[0].claimedAt, 0, "Withdrawal should be claimed");
    }

    function test_GetAccountWithdraws_MultipleAccounts() public withMinimumStakeBalance {
        address user2 = makeAddr("user2");

        uint256 vhypeAmount1 = 2_000 * 1e18;
        uint256 vhypeAmount2 = 3_000 * 1e18;

        // User 1 creates 2 withdrawals
        uint256 withdrawId1 = _setupWithdraw(user, vhypeAmount1);
        uint256 withdrawId2 = _setupWithdraw(user, vhypeAmount2);

        // User 2 creates 1 withdrawal
        uint256 withdrawId3 = _setupWithdraw(user2, vhypeAmount1);

        // Check user 1's withdrawals
        StakingVaultManager.Withdraw[] memory withdraws1 = stakingVaultManager.getAccountWithdraws(user);
        assertEq(withdraws1.length, 2, "User 1 should have 2 withdrawals");
        assertEq(withdraws1[0].id, withdrawId1, "User 1 first withdrawal ID should match");
        assertEq(withdraws1[1].id, withdrawId2, "User 1 second withdrawal ID should match");
        assertEq(withdraws1[0].account, user, "User 1 withdrawals should belong to user 1");
        assertEq(withdraws1[1].account, user, "User 1 withdrawals should belong to user 1");

        // Check user 2's withdrawals
        StakingVaultManager.Withdraw[] memory withdraws2 = stakingVaultManager.getAccountWithdraws(user2);
        assertEq(withdraws2.length, 1, "User 2 should have 1 withdrawal");
        assertEq(withdraws2[0].id, withdrawId3, "User 2 withdrawal ID should match");
        assertEq(withdraws2[0].account, user2, "User 2 withdrawal should belong to user 2");
    }

    function test_GetAccountWithdraws_WithSplitWithdrawals() public withMinimumStakeBalance {
        // Queue a large withdrawal that will be split
        uint256 vhypeAmount = 25_000 * 1e18; // 25k vHYPE (will be split into 3 withdrawals: 10k + 10k + 5k)

        // Transfer vHYPE to user and approve
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);
        vm.stopPrank();

        // Should have created 3 split withdrawals
        assertEq(withdrawIds.length, 3, "Should create 3 split withdrawals");

        StakingVaultManager.Withdraw[] memory withdraws = stakingVaultManager.getAccountWithdraws(user);

        // All split withdrawals should be returned
        assertEq(withdraws.length, 3, "Should return all 3 split withdrawals");
        assertEq(withdraws[0].id, withdrawIds[0], "First withdrawal ID should match");
        assertEq(withdraws[1].id, withdrawIds[1], "Second withdrawal ID should match");
        assertEq(withdraws[2].id, withdrawIds[2], "Third withdrawal ID should match");

        // Verify total amount equals original request
        uint256 totalVhype = withdraws[0].vhypeAmount + withdraws[1].vhypeAmount + withdraws[2].vhypeAmount;
        assertEq(totalVhype, vhypeAmount, "Total vHYPE should equal original request");
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

    function test_TotalBalance_WithReservedHypeForWithdraws() public withExcessStakeBalance {
        uint256 vhypeSupply = vHYPE.totalSupply();
        uint256 vhypeWithdrawAmount = 100_000 * 1e18;

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeWithdrawAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Test totalBalance after processing (should subtract reservedHypeForWithdraws)
        assertEq(stakingVaultManager.totalBalance(), MINIMUM_STAKE_BALANCE);

        // Verify the reserved amount calculation
        assertEq(stakingVaultManager.totalHypeProcessed(), vhypeWithdrawAmount);
        assertEq(stakingVaultManager.totalHypeClaimed(), 0);

        // Mock a 50% slash
        _mockDelegations(validator, (vhypeSupply / 2).to8Decimals());

        // Apply the slash
        vm.prank(owner);
        stakingVaultManager.applySlash(0, 0.5e18);

        // Test totalBalance after slash
        // 600k HYPE slashed to 300k HYPE
        // 100k HYPE withdraw reserve slashed to 50k HYPE
        // So we expect 250k HYPE in total balance
        assertEq(stakingVaultManager.totalBalance(), 250_000 * 1e18);
    }

    function test_TotalBalance_ReservedHypeForWithdrawsGreaterThanAccountBalance() public withExcessStakeBalance {
        uint256 vhypeWithdrawAmount = 100_000 * 1e18;

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeWithdrawAmount);

        // Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Test totalBalance after processing (should subtract reservedHypeForWithdraws)
        assertEq(stakingVaultManager.totalBalance(), MINIMUM_STAKE_BALANCE);

        // Verify the reserved amount calculation
        assertEq(stakingVaultManager.totalHypeProcessed(), vhypeWithdrawAmount);
        assertEq(stakingVaultManager.totalHypeClaimed(), 0);

        // Mock a 100% slash
        _mockDelegations(validator, 0);

        // Test totalBalance after slash
        // 600k HYPE slashed to 300k HYPE
        // 100k HYPE withdraw reserve slashed to 50k HYPE
        // So we expect 250k HYPE in total balance
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVaultManager.AccountBalanceLessThanReservedHypeForWithdraws.selector)
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
            delegated: 0, undelegated: 0, totalPendingWithdrawal: 0, nPendingWithdrawals: 0
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: HYPETovHYPE and vHYPEtoHYPE Functions       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_HYPETovHYPE_ExchangeRateAboveOne() public withExchangeRate(4e18, 2e18) {
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 1e18);
    }

    function test_HYPETovHYPE_ExchangeRateBelowOne() public withExchangeRate(2e18, 4e18) {
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 4e18);
    }

    function test_HYPETovHYPE_ZeroAmount() public withExchangeRate(4e18, 2e18) {
        assertEq(stakingVaultManager.HYPETovHYPE(0), 0);
    }

    function test_HYPETovHYPE_ZeroExchangeRate_ZeroBalance() public withExchangeRate(0, 2e18) {
        assertEq(stakingVaultManager.HYPETovHYPE(1e18), 0);
    }

    function test_HYPETovHYPE_OneExchangeRate_ZeroSupply() public withExchangeRate(2e18, 0) {
        assertEq(stakingVaultManager.HYPETovHYPE(2e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateAboveOne() public withExchangeRate(4e18, 2e18) {
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 2e18);
    }

    function test_vHYPEtoHYPE_ExchangeRateBelowOne() public withExchangeRate(2e18, 4e18) {
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 0.5e18);
    }

    function test_vHYPEtoHYPE_ZeroAmount() public withExchangeRate(4e18, 2e18) {
        assertEq(stakingVaultManager.vHYPEtoHYPE(0), 0);
    }

    function test_vHYPEtoHYPE_ZeroExchangeRate_ZeroBalance() public withExchangeRate(0, 2e18) {
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 0);
    }

    function test_vHYPEtoHYPE_OneExchangeRate_ZeroSupply() public withExchangeRate(2e18, 0) {
        assertEq(stakingVaultManager.vHYPEtoHYPE(1e18), 1e18);
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

    function test_SetMinimumStakeBalance_TooLowDuringBatchProcessing() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Process the batch (but don't finalize it yet)
        stakingVaultManager.processBatch(type(uint256).max);

        // Calculate the new minimum stake balance that would be too high
        // Total balance is 600k, batch processed 100k, so we need at least 500k minimum stake balance
        // Setting it to 500k + 1 should fail
        uint256 newMinimumStakeBalanceTooLarge = vHYPE.totalSupply() - vhypeAmount + 1;

        vm.prank(owner);
        vm.expectRevert(IStakingVaultManager.MinimumStakeBalanceTooLarge.selector);
        stakingVaultManager.setMinimumStakeBalance(newMinimumStakeBalanceTooLarge);
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

    function test_SetMinimumDepositAmount_UpdatesDepositValidation() public withMinimumStakeBalance {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE
        uint256 belowNewMinimum = newMinimumAmount - 1; // 1 wei below new minimum

        // Set new minimum amount
        vm.prank(owner);
        stakingVaultManager.setMinimumDepositAmount(newMinimumAmount);

        // Try to deposit below new minimum - should fail
        vm.deal(user, belowNewMinimum);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.BelowMinimumDepositAmount.selector));
        stakingVaultManager.deposit{value: belowNewMinimum}();

        // Deposit exactly the new minimum - should succeed
        vm.deal(user, newMinimumAmount);
        stakingVaultManager.deposit{value: newMinimumAmount}();

        // Verify deposit succeeded
        assertEq(vHYPE.balanceOf(user), newMinimumAmount);
        assertEq(address(stakingVault).balance, newMinimumAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       Tests: Set Minimum Withdraw Amount (Only Owner)      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMinimumWithdrawAmount_OnlyOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.prank(owner);
        stakingVaultManager.setMinimumWithdrawAmount(newMinimumAmount);

        assertEq(stakingVaultManager.minimumWithdrawAmount(), newMinimumAmount);
    }

    function test_SetMinimumWithdrawAmount_NotOwner() public {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setMinimumWithdrawAmount(newMinimumAmount);
    }

    function test_SetMinimumWithdrawAmount_UpdatesWithdrawValidation() public withMinimumStakeBalance {
        uint256 newMinimumAmount = 5e16; // 0.05 HYPE
        uint256 belowNewMinimum = newMinimumAmount - 1; // 1 wei below new minimum

        // Give user some vHYPE
        vm.prank(owner);
        vHYPE.transfer(user, 1e18);

        // Set new minimum amount
        vm.prank(owner);
        stakingVaultManager.setMinimumWithdrawAmount(newMinimumAmount);

        // Try to withdraw below new minimum - should fail
        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), belowNewMinimum);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.BelowMinimumWithdrawAmount.selector));
        stakingVaultManager.queueWithdraw(belowNewMinimum);

        // Withdraw exactly the new minimum - should succeed
        vHYPE.approve(address(stakingVaultManager), newMinimumAmount);
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(newMinimumAmount);

        // Verify withdraw succeeded
        assertEq(withdrawIds.length, 1);
        assertEq(withdrawIds[0], 1);
        assertEq(vHYPE.balanceOf(address(stakingVaultManager)), newMinimumAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Tests: Set Claim Window Buffer (Only Owner)        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetClaimWindowBuffer_OnlyOwner() public {
        uint256 newClaimWindowBuffer = 14 days;

        // Owner can set claim window buffer
        vm.prank(owner);
        stakingVaultManager.setClaimWindowBuffer(newClaimWindowBuffer);
        assertEq(stakingVaultManager.claimWindowBuffer(), newClaimWindowBuffer, "Claim window buffer should be updated");
    }

    function test_SetClaimWindowBuffer_NotOwner() public {
        uint256 newClaimWindowBuffer = 14 days;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setClaimWindowBuffer(newClaimWindowBuffer);
    }

    function test_SetClaimWithdrawBuffer_UpdatesClaimWithdrawValidation() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: User queues a withdraw
        uint256 withdrawId = _setupWithdraw(user, vhypeAmount);

        // Process and finalize the batch
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Fast-forward time to make withdraw claimable (7 days + 1 second)
        warp(vm.getBlockTimestamp() + 7 days + 1);

        // User claims the withdraw
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.WithdrawUnclaimable.selector));
        stakingVaultManager.claimWithdraw(withdrawId, user);
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

    function test_ResetBatch_Success() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 30k vHYPE
        uint256 vhypeAmount3 = 2_000 * 1e18; // 20k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

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
            "Batch should have 8k vHYPE processed"
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

    function test_ResetBatch_WithCancelledWithdrawals() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 5_000 * 1e18; // 50k vHYPE
        uint256 vhypeAmount2 = 3_000 * 1e18; // 30k vHYPE (will be cancelled)
        uint256 vhypeAmount3 = 2_000 * 1e18; // 20k vHYPE
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

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
        vm.expectRevert(IStakingVaultManager.NothingToReset.selector);
        stakingVaultManager.resetBatch(type(uint256).max);
    }

    function test_ResetBatch_CannotResetFinalizedBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Try to reset - should fail
        vm.startPrank(owner);
        vm.expectRevert(IStakingVaultManager.NothingToReset.selector);
        stakingVaultManager.resetBatch(type(uint256).max);
    }

    function test_ResetBatch_NotOwner() public withExcessStakeBalance {
        uint256 vhypeAmount = 50_000 * 1e18;

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

    function test_FinalizeResetBatch_Success() public withExcessStakeBalance {
        uint256 vhypeAmount = 50_000 * 1e18;

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

    function test_FinalizeResetBatch_FailsWithPartialReset() public withExcessStakeBalance {
        uint256 vhypeAmount1 = 3_000 * 1e18;
        uint256 vhypeAmount2 = 2_000 * 1e18;

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
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.InvalidBatch.selector, batchIndex));
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_FailsWithNoBatch() public {
        // Try to finalize when no batch exists
        vm.prank(owner);
        vm.expectRevert(IStakingVaultManager.NothingToFinalize.selector);
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_FailsWithFinalizedBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 50_000 * 1e18;

        // Queue and process withdrawal
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Mock finalization calls
        expectCoreWriterCall(CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator, vhypeAmount.to8Decimals(), true));
        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode(vhypeAmount.to8Decimals()));

        // Finalize the batch normally
        stakingVaultManager.finalizeBatch();

        // Try to finalize reset - should fail because currentBatchIndex moved past the finalized batch
        // and there's no current batch to reset
        vm.prank(owner);
        vm.expectRevert(IStakingVaultManager.NothingToFinalize.selector);
        stakingVaultManager.finalizeResetBatch();
    }

    function test_FinalizeResetBatch_NotOwner() public withExcessStakeBalance {
        uint256 vhypeAmount = 50_000 * 1e18;

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

    function test_ResetBatch_StopsAtPreviousBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 2_000 * 1e18; // 2k vHYPE

        // Setup: Queue and process 3 withdrawals in batch 0
        _setupWithdraw(user, vhypeAmount);
        _setupWithdraw(user, vhypeAmount);
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);
        stakingVaultManager.finalizeBatch();

        // Advance time to allow next batch
        warp(vm.getBlockTimestamp() + 1 days + 1 seconds);

        // Queue and process 2 more withdrawals in batch 1
        _setupWithdraw(user, vhypeAmount);
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Verify state before reset
        assertEq(stakingVaultManager.getBatchesLength(), 2, "Should have 2 batches");
        assertEq(stakingVaultManager.currentBatchIndex(), 1, "Current batch index should be 1");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 5, "Last processed withdraw ID should be 5");
        assertEq(stakingVaultManager.getBatch(1).vhypeProcessed, vhypeAmount * 2, "Batch 1 should have 2 withdrawals");

        // Verify withdraw batch assignments
        assertEq(stakingVaultManager.getWithdraw(1).batchIndex, 0, "Withdraw 1 should be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(2).batchIndex, 0, "Withdraw 2 should be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(3).batchIndex, 0, "Withdraw 3 should be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(4).batchIndex, 1, "Withdraw 4 should be in batch 1");
        assertEq(stakingVaultManager.getWithdraw(5).batchIndex, 1, "Withdraw 5 should be in batch 1");

        // Reset batch 1 with a high number of withdrawals (more than in batch 1)
        // This should reset batch 1 completely but stop when it hits batch 0 withdrawals
        vm.prank(owner);
        stakingVaultManager.resetBatch(type(uint256).max);

        // Verify batch 1 was fully reset
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 3, "Should stop at last withdraw of batch 0");
        assertEq(stakingVaultManager.getBatch(1).vhypeProcessed, 0, "Batch 1 should be fully reset");

        // Verify batch 1 withdrawals were unassigned
        assertEq(stakingVaultManager.getWithdraw(4).batchIndex, type(uint256).max, "Withdraw 4 should be unassigned");
        assertEq(stakingVaultManager.getWithdraw(5).batchIndex, type(uint256).max, "Withdraw 5 should be unassigned");

        // Verify batch 0 withdrawals are still assigned to batch 0
        assertEq(stakingVaultManager.getWithdraw(1).batchIndex, 0, "Withdraw 1 should still be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(2).batchIndex, 0, "Withdraw 2 should still be in batch 0");
        assertEq(stakingVaultManager.getWithdraw(3).batchIndex, 0, "Withdraw 3 should still be in batch 0");

        // Verify batch 0 is unchanged
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, vhypeAmount * 3, "Batch 0 should be unchanged");
        assertGt(stakingVaultManager.getBatch(0).finalizedAt, 0, "Batch 0 should still be finalized");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*            Tests: Switch Validator (Only Owner)            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SwitchValidator_OnlyOwner() public withMinimumStakeBalance {
        // Current validator should be defaultValidator
        assertEq(stakingVaultManager.validator(), validator);

        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator, MINIMUM_STAKE_BALANCE.to8Decimals(), true)
        );
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator2, MINIMUM_STAKE_BALANCE.to8Decimals(), false)
        );

        vm.prank(owner);
        stakingVaultManager.switchValidator(validator2);

        // Verify validator was updated
        assertEq(stakingVaultManager.validator(), validator2);
    }

    function test_SwitchValidator_ZeroBalance() public {
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator, MINIMUM_STAKE_BALANCE.to8Decimals(), true), 0
        );
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator2, MINIMUM_STAKE_BALANCE.to8Decimals(), false), 0
        );

        vm.prank(owner);
        stakingVaultManager.switchValidator(validator2);

        // Verify validator was updated
        assertEq(stakingVaultManager.validator(), validator2);
    }

    function test_SwitchValidator_NotOwner() public withMinimumStakeBalance {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.switchValidator(validator2);
    }

    function test_SwitchValidator_SameValidator() public withMinimumStakeBalance {
        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.RedelegateToSameValidator.selector);
        stakingVaultManager.switchValidator(validator);
    }

    function test_SwitchValidator_StakeLockedUntilFuture() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 futureTimestamp = uint64(vm.getBlockTimestamp() + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(validator, amount.to8Decimals(), futureTimestamp);

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVaultManager.switchValidator(validator2);
    }

    function test_SwitchValidator_StakeUnlockedAtExactTimestamp() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 currentTimestamp = uint64(vm.getBlockTimestamp()); // Exact current timestamp

        _mockDelegationsWithLock(validator, amount.to8Decimals(), currentTimestamp);

        // Mock the undelegate call (from current validator)
        expectCoreWriterCall(CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator, amount.to8Decimals(), true));
        // Mock the delegate call (to new validator)
        expectCoreWriterCall(CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator2, amount.to8Decimals(), false));

        vm.prank(owner);
        stakingVaultManager.switchValidator(validator2);

        // Verify validator was updated
        assertEq(stakingVaultManager.validator(), validator2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             Tests: Emergency Withdraw (Only Owner)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_EmergencyStakingWithdraw_OnlyOwner() public withMinimumStakeBalance {
        uint256 withdrawAmount = 100_000 * 1e18; // 100k HYPE (in 18 decimals)

        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode(withdrawAmount.to8Decimals()));
        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE,
            abi.encode(stakingVaultManager.validator(), withdrawAmount.to8Decimals(), true)
        );

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyStakingWithdraw(owner, withdrawAmount, "Emergency staking withdraw");
        stakingVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_NotOwner() public withMinimumStakeBalance {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.emergencyStakingWithdraw(1_000_000 * 1e18, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_InsufficientBalance() public withMinimumStakeBalance {
        uint256 withdrawAmount = MINIMUM_STAKE_BALANCE + 1e18;

        vm.startPrank(owner);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVaultManager.emergencyStakingWithdraw(withdrawAmount, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_ZeroAmount() public withMinimumStakeBalance {
        vm.startPrank(owner);
        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode(0), 0);
        stakingVaultManager.emergencyStakingWithdraw(0, "Emergency staking withdraw");
    }

    function test_EmergencyStakingWithdraw_StakeLockedUntilFuture() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 futureTimestamp = uint64(vm.getBlockTimestamp() + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(validator, amount.to8Decimals(), futureTimestamp);

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVaultManager.emergencyStakingWithdraw(amount, "Emergency withdraw");
    }

    function test_EmergencyStakingWithdraw_StakeUnlockedAtExactTimestamp() public {
        uint256 amount = 100_000 * 1e18; // 100k HYPE
        uint64 currentTimestamp = uint64(vm.getBlockTimestamp()); // Exact current timestamp

        _mockDelegationsWithLock(validator, amount.to8Decimals(), currentTimestamp);

        expectCoreWriterCall(CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(validator, amount.to8Decimals(), true));
        expectCoreWriterCall(CoreWriterLibrary.STAKING_WITHDRAW, abi.encode(amount.to8Decimals()));

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

        expectCoreWriterCall(
            CoreWriterLibrary.TOKEN_DELEGATE, abi.encode(stakingVaultManager.validator(), depositWeiAmount, false)
        );
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode(depositWeiAmount));

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
        expectCoreWriterCall(CoreWriterLibrary.STAKING_DEPOSIT, abi.encode(0), 0);
        stakingVaultManager.emergencyStakingDeposit(0, "Emergency staking deposit");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Upgradeability                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction();

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
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.upgradeToAndCall(address(newImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   Tests: Wind Down (Only Owner)            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_WindDown_AllowsAllWithdrawalsToBeProcessed() public withMinimumStakeBalance {
        // Initial state: minimum stake balance is set
        assertEq(stakingVaultManager.minimumStakeBalance(), MINIMUM_STAKE_BALANCE, "Should have minimum stake");

        // Total balance available
        uint256 totalBalance = stakingVaultManager.totalBalance();
        assertEq(totalBalance, MINIMUM_STAKE_BALANCE, "Total balance should equal minimum stake");

        // Queue withdrawals that would exceed capacity with minimum stake balance
        // Note: large withdrawals get split into chunks of max 10k each
        uint256 vhypeAmount = MINIMUM_STAKE_BALANCE; // Queue full balance (500k)
        _setupWithdraw(user, vhypeAmount);

        // Calculate expected number of withdraw chunks (500k / 10k = 50)
        uint256 expectedChunks = vhypeAmount / MAXIMUM_WITHDRAW_AMOUNT;

        // Try to process with minimum stake balance - should not process any withdrawals
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);
        assertEq(numProcessed, 0, "Should not process withdrawals with minimum stake balance");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), 0, "No withdrawals should be processed");

        // Call windDown to set minimum stake balance to 0
        vm.prank(owner);
        stakingVaultManager.windDown();

        // Verify minimum stake balance is now 0
        assertEq(stakingVaultManager.minimumStakeBalance(), 0, "Minimum stake should be 0 after wind down");

        // Now all withdrawals should be processable
        numProcessed = stakingVaultManager.processBatch(type(uint256).max);
        assertEq(numProcessed, expectedChunks, "Should process all withdrawal chunks after wind down");
        assertEq(stakingVaultManager.lastProcessedWithdrawId(), expectedChunks, "All withdrawals should be processed");

        // Verify the withdrawals were assigned to a batch
        for (uint256 i = 1; i <= expectedChunks; i++) {
            assertEq(stakingVaultManager.getWithdraw(i).batchIndex, 0, "Withdrawal should be in batch 0");
        }

        // Verify batch has all withdrawals
        assertEq(
            stakingVaultManager.getBatch(0).vhypeProcessed, vhypeAmount, "Batch should have processed all withdrawals"
        );
    }

    function test_WindDown_MultipleWithdrawals() public withMinimumStakeBalance {
        uint256 totalBalance = stakingVaultManager.totalBalance();

        // Use smaller amounts that won't be split
        uint256 vhypeAmount1 = 5_000 * 1e18; // 5k vHYPE
        uint256 vhypeAmount2 = 7_000 * 1e18; // 7k vHYPE
        uint256 vhypeAmount3 = 8_000 * 1e18; // 8k vHYPE (total 20k, more than excess balance)

        // Queue multiple withdrawals that total more than (balance - minimumStake)
        _setupWithdraw(user, vhypeAmount1);
        _setupWithdraw(user, vhypeAmount2);
        _setupWithdraw(user, vhypeAmount3);

        // With minimum stake balance, some withdrawals won't process
        uint256 numProcessed = stakingVaultManager.processBatch(type(uint256).max);
        uint256 firstBatchProcessed = numProcessed;
        assertEq(numProcessed, 0, "Should not process any withdrawals with minimum stake");
        assertEq(stakingVaultManager.getBatch(0).vhypeProcessed, 0, "Batch should have no processed vHYPE");
        stakingVaultManager.finalizeBatch();

        // Call windDown
        vm.prank(owner);
        stakingVaultManager.windDown();

        // Fast forward time to allow withdrawals to process
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // Now all withdrawals should be processable
        numProcessed = stakingVaultManager.processBatch(type(uint256).max);
        assertEq(numProcessed, 3, "Should process all 3 withdrawals after wind down");

        // Verify all withdrawals were assigned to batch
        assertEq(stakingVaultManager.getWithdraw(1).batchIndex, 1, "Withdrawal 1 should be in batch 1");
        assertEq(stakingVaultManager.getWithdraw(2).batchIndex, 1, "Withdrawal 2 should be in batch 1");
        assertEq(stakingVaultManager.getWithdraw(3).batchIndex, 1, "Withdrawal 3 should be in batch 1");

        // Verify batch has all withdrawals
        assertEq(
            stakingVaultManager.getBatch(1).vhypeProcessed,
            vhypeAmount1 + vhypeAmount2 + vhypeAmount3,
            "Batch should have processed all withdrawals"
        );
    }

    function test_WindDown_OnlyOwner() public {
        // Try to call windDown as non-owner
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.windDown();

        // Verify minimum stake balance unchanged
        assertEq(stakingVaultManager.minimumStakeBalance(), MINIMUM_STAKE_BALANCE, "Should still have minimum stake");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             Tests: Set Maximum Withdraw Amount             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMaximumWithdrawAmount_OnlyOwner() public {
        uint256 newMaxAmount = 5_000 * 1e18; // 5k HYPE

        // Owner can set maximum withdraw amount
        vm.prank(owner);
        stakingVaultManager.setMaximumWithdrawAmount(newMaxAmount);

        assertEq(stakingVaultManager.maximumWithdrawAmount(), newMaxAmount, "Maximum withdraw amount should be updated");
    }

    function test_SetMaximumWithdrawAmount_NotOwner() public {
        uint256 newMaxAmount = 5_000 * 1e18; // 5k HYPE

        // Non-owner cannot set maximum withdraw amount
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.setMaximumWithdrawAmount(newMaxAmount);

        // Verify maximum withdraw amount unchanged
        assertEq(
            stakingVaultManager.maximumWithdrawAmount(),
            MAXIMUM_WITHDRAW_AMOUNT,
            "Maximum withdraw amount should not change"
        );
    }

    function test_SetMaximumWithdrawAmount_AffectsWithdrawalSplitting() public withMinimumStakeBalance {
        // Set a smaller maximum withdraw amount
        uint256 newMaxAmount = 2_000 * 1e18; // 2k HYPE (down from 10k)

        vm.prank(owner);
        stakingVaultManager.setMaximumWithdrawAmount(newMaxAmount);

        // Queue a withdraw that exceeds the new maximum
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Transfer vHYPE to user and approve
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);
        vm.stopPrank();

        // Should be split into 3 withdraws: 2k + 2k + 1k
        assertEq(withdrawIds.length, 3, "Should create 3 withdrawals with new max amount");

        // Verify each withdrawal amount
        StakingVaultManager.Withdraw memory withdraw1 = stakingVaultManager.getWithdraw(withdrawIds[0]);
        StakingVaultManager.Withdraw memory withdraw2 = stakingVaultManager.getWithdraw(withdrawIds[1]);
        StakingVaultManager.Withdraw memory withdraw3 = stakingVaultManager.getWithdraw(withdrawIds[2]);

        uint256 expectedMaxVhype = stakingVaultManager.HYPETovHYPE(newMaxAmount);

        assertEq(withdraw1.vhypeAmount, expectedMaxVhype, "First withdraw should be max amount");
        assertEq(withdraw2.vhypeAmount, expectedMaxVhype, "Second withdraw should be max amount");
        assertEq(
            withdraw1.vhypeAmount + withdraw2.vhypeAmount + withdraw3.vhypeAmount,
            vhypeAmount,
            "Total should equal requested amount"
        );
    }

    function test_SetMaximumWithdrawAmount_LargerAmount_FewerSplits() public withMinimumStakeBalance {
        // Set a larger maximum withdraw amount
        uint256 newMaxAmount = 20_000 * 1e18; // 20k HYPE (up from 10k)

        vm.prank(owner);
        stakingVaultManager.setMaximumWithdrawAmount(newMaxAmount);

        // Queue a withdraw that would have been split with old limit
        uint256 vhypeAmount = 15_000 * 1e18; // 15k vHYPE

        // Transfer vHYPE to user and approve
        vm.prank(owner);
        vHYPE.transfer(user, vhypeAmount);

        vm.startPrank(user);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);
        vm.stopPrank();

        // Should create only 1 withdrawal now (vs 2 with old 10k limit)
        assertEq(withdrawIds.length, 1, "Should create 1 withdrawal with new max amount");

        StakingVaultManager.Withdraw memory withdraw = stakingVaultManager.getWithdraw(withdrawIds[0]);
        assertEq(withdraw.vhypeAmount, vhypeAmount, "Single withdraw should be full amount");
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
        StakingVaultManagerWithExtraFunction newImplementation = new StakingVaultManagerWithExtraFunction();
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
        StakingVaultManagerWithExtraFunction anotherImplementation = new StakingVaultManagerWithExtraFunction();
        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        stakingVaultManager.upgradeToAndCall(address(anotherImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Apply Slash (Only Owner)               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_ApplySlash_ValidBatch() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
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
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.InvalidBatch.selector, 999));
        stakingVaultManager.applySlash(999, 5e17);
    }

    function test_ApplySlash_NotOwner() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Try to apply slash as non-owner
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        stakingVaultManager.applySlash(0, 5e17);
    }

    function test_ApplySlash_ZeroSlashedExchangeRate() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
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

    function test_ApplySlash_MultipleBatches() public withExcessStakeBalance {
        uint256 vhypeAmount = 5_000 * 1e18; // 5k vHYPE

        // Setup: Create first batch
        _setupWithdraw(user, vhypeAmount);
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the first batch
        stakingVaultManager.finalizeBatch();

        // Fast forward by 1 day
        warp(vm.getBlockTimestamp() + 1 days + 1);

        // Setup: Create second batch
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
        assertEq(stakingVaultManager.totalHypeProcessed(), 2_500 * 1e18 + 1_000 * 1e18);
    }

    function test_ApplySlash_ReapplySlash() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
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

    function test_ApplySlash_CannotSlashOutsideSlashWindow() public withExcessStakeBalance {
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Finalize the batch
        stakingVaultManager.finalizeBatch();

        // Move time forward past the slash window
        warp(vm.getBlockTimestamp() + 7 days + stakingVaultManager.claimWindowBuffer() + 1);

        // Try to apply a slash outside the slash window
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.CannotSlashBatchOutsideSlashWindow.selector, 0));
        stakingVaultManager.applySlash(0, 5e17);
    }

    function test_ApplySlash_UnfinalizedBatch() public withExcessStakeBalance {
        uint256 originalBalance = vHYPE.totalSupply();
        uint256 vhypeAmount = 100_000 * 1e18; // 100k vHYPE

        // Setup: User queues a withdraw
        _setupWithdraw(user, vhypeAmount);

        // Setup: Process the batch
        stakingVaultManager.processBatch(type(uint256).max);

        // Slash occurs
        _mockDelegations(validator, (originalBalance / 2).to8Decimals());

        // The batch has the original exchange rate
        StakingVaultManager.Batch memory batch = stakingVaultManager.getBatch(0);
        assertEq(batch.snapshotExchangeRate, 1e18);

        // Try to apply a slash to an unfinalized batch
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IStakingVaultManager.InvalidBatch.selector, 0));
        stakingVaultManager.applySlash(0, 5e17);

        // Reset the batch
        stakingVaultManager.resetBatch(type(uint256).max);
        stakingVaultManager.finalizeResetBatch();

        // Now process the batch - should be slashed
        stakingVaultManager.processBatch(type(uint256).max);
        batch = stakingVaultManager.getBatch(0);
        assertEq(batch.snapshotExchangeRate, 5e17);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Helper Functions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to setup a user with vHYPE and queue a withdraw
    /// @param withdrawUser The user to setup
    /// @param vhypeAmount The amount of vHYPE to mint and queue for withdrawal
    /// @return withdrawId The ID of the queued withdraw
    function _setupWithdraw(address withdrawUser, uint256 vhypeAmount) internal returns (uint256 withdrawId) {
        // Transfer vHYPE to the user
        vm.prank(owner);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        vHYPE.transfer(withdrawUser, vhypeAmount);

        // User approves and queues withdraw
        vm.startPrank(withdrawUser);
        vHYPE.approve(address(stakingVaultManager), vhypeAmount);
        uint256[] memory withdrawIds = stakingVaultManager.queueWithdraw(vhypeAmount);
        vm.stopPrank();

        return withdrawIds[0];
    }

    function _mockDelegations(address _validator, uint64 weiAmount) internal {
        _mockDelegationsWithLock(_validator, weiAmount, 0);
    }

    function _mockDelegationsWithLock(address _validator, uint64 weiAmount, uint64 lockedUntilTimestamp) internal {
        hl.mockDelegation(
            address(stakingVault),
            L1ReadLibrary.Delegation({
                validator: _validator, amount: weiAmount, lockedUntilTimestamp: lockedUntilTimestamp
            })
        );
    }

    modifier withMinimumStakeBalance() {
        _mockBalancesForExchangeRate(MINIMUM_STAKE_BALANCE, MINIMUM_STAKE_BALANCE);
        _;
    }

    modifier withExcessStakeBalance() {
        uint256 excess = 100_000 * 1e18;
        _mockBalancesForExchangeRate(MINIMUM_STAKE_BALANCE + excess, MINIMUM_STAKE_BALANCE + excess);
        _;
    }

    modifier withExcessStakeBalanceAmount(uint256 excess) {
        _mockBalancesForExchangeRate(MINIMUM_STAKE_BALANCE + excess, MINIMUM_STAKE_BALANCE + excess);
        _;
    }

    modifier underMinimumStakeBalance() {
        uint256 excess = 100_000 * 1e18;
        _mockBalancesForExchangeRate(MINIMUM_STAKE_BALANCE - excess, MINIMUM_STAKE_BALANCE - excess);
        _;
    }

    modifier withExchangeRate(uint256 totalBalance, uint256 totalSupply) {
        _mockBalancesForExchangeRate(totalBalance, totalSupply);
        _;
    }

    /// @dev Helper function to mock balances for testing exchange rate calculations
    /// @param totalBalance The total balance of HYPE to mock (in 18 decimals)
    /// @param totalSupply The total supply of vHYPE to mint to owner (in 18 decimals)
    function _mockBalancesForExchangeRate(uint256 totalBalance, uint256 totalSupply) internal {
        vm.assume(totalBalance.to8Decimals() <= type(uint64).max);

        uint64 delegatedBalance = totalBalance > 0 ? totalBalance.to8Decimals() : 0; // Convert to 8 decimals

        // Mock delegations
        _mockDelegations(validator, delegatedBalance);

        // Mint vHYPE supply to owner
        if (totalSupply > 0) {
            vm.prank(address(stakingVaultManager));
            vHYPE.mint(owner, totalSupply);
        }
    }
}

contract StakingVaultManagerWithExtraFunction is StakingVaultManager {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
