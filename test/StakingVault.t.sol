// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {IStakingVault} from "../src/interfaces/IStakingVault.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {Base} from "../src/Base.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StakingVaultTest is Test {
    RoleRegistry roleRegistry;
    StakingVault stakingVault;

    uint64 public constant HYPE_TOKEN_ID = 150; // Mainnet HYPE token ID

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public operator = makeAddr("operator");
    address public validator = makeAddr("validator");
    address public validator2 = makeAddr("validator2");

    function setUp() public {
        RoleRegistry roleRegistryImplementation = new RoleRegistry();
        bytes memory roleRegistryInitData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);
        ERC1967Proxy roleRegistryProxy = new ERC1967Proxy(address(roleRegistryImplementation), roleRegistryInitData);
        roleRegistry = RoleRegistry(address(roleRegistryProxy));

        address[] memory whitelistedValidators = new address[](2);
        whitelistedValidators[0] = validator;
        whitelistedValidators[1] = validator2;
        StakingVault stakingVaultImplementation = new StakingVault(HYPE_TOKEN_ID);
        bytes memory stakingVaultInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(roleRegistryProxy), whitelistedValidators);
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        stakingVault = StakingVault(payable(stakingVaultProxy));

        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), manager);
        roleRegistry.grantRole(roleRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock the core user exists check to return true
        _mockCoreUserExists(address(stakingVault), true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Tests: Stake                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Stake_Success(uint64 weiAmount) public {
        vm.assume(weiAmount > 0);
        vm.assume(weiAmount < type(uint64).max);

        // Mock the CoreWriter call to deposit
        bytes memory encodedActionDeposit = abi.encode(weiAmount);
        bytes memory dataDeposit = new bytes(4 + encodedActionDeposit.length);
        dataDeposit[0] = 0x01;
        dataDeposit[1] = 0x00;
        dataDeposit[2] = 0x00;
        dataDeposit[3] = 0x04; // Staking deposit action ID
        for (uint256 i = 0; i < encodedActionDeposit.length; i++) {
            dataDeposit[4 + i] = encodedActionDeposit[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataDeposit),
            abi.encode()
        );

        // Mock the CoreWriter call to delegate
        bytes memory encodedActionDelegate = abi.encode(validator, weiAmount, false);
        bytes memory dataDelegate = new bytes(4 + encodedActionDelegate.length);
        dataDelegate[0] = 0x01;
        dataDelegate[1] = 0x00;
        dataDelegate[2] = 0x00;
        dataDelegate[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < encodedActionDelegate.length; i++) {
            dataDelegate[4 + i] = encodedActionDelegate[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataDelegate),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataDeposit));
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataDelegate));

        vm.prank(manager);
        stakingVault.stake(validator, weiAmount);

        // Verify lastDelegationChangeBlockNumber was updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_Stake_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        vm.deal(notManager, 1e18);
        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.stake(validator, 1e10);
    }

    function test_Stake_ZeroAmount() public {
        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.stake(validator, 0);
    }

    function test_Stake_CanCallTwiceInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock the CoreWriter call to deposit
        bytes memory encodedActionDeposit = abi.encode(weiAmount);
        bytes memory dataDeposit = new bytes(4 + encodedActionDeposit.length);
        dataDeposit[0] = 0x01;
        dataDeposit[1] = 0x00;
        dataDeposit[2] = 0x00;
        dataDeposit[3] = 0x04; // Staking deposit action ID
        for (uint256 i = 0; i < encodedActionDeposit.length; i++) {
            dataDeposit[4 + i] = encodedActionDeposit[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataDeposit),
            abi.encode()
        );

        // Mock the CoreWriter call to delegate
        bytes memory encodedActionDelegate = abi.encode(validator, weiAmount, false);
        bytes memory dataDelegate = new bytes(4 + encodedActionDelegate.length);
        dataDelegate[0] = 0x01;
        dataDelegate[1] = 0x00;
        dataDelegate[2] = 0x00;
        dataDelegate[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < encodedActionDelegate.length; i++) {
            dataDelegate[4 + i] = encodedActionDelegate[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataDelegate),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataDeposit), 2);
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataDelegate), 2);

        vm.startPrank(manager);
        stakingVault.stake(validator, weiAmount);
        stakingVault.stake(validator, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Tests: Unstake                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Unstake_Success(uint64 weiAmount) public {
        vm.assume(weiAmount > 0);

        /// Mock a delegation before undelegate
        _mockDelegations(validator, weiAmount);

        // Mock the CoreWriter call
        bytes memory encodedActionUndelegate = abi.encode(validator, weiAmount, true);
        bytes memory dataUndelegate = new bytes(4 + encodedActionUndelegate.length);
        dataUndelegate[0] = 0x01;
        dataUndelegate[1] = 0x00;
        dataUndelegate[2] = 0x00;
        dataUndelegate[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < encodedActionUndelegate.length; i++) {
            dataUndelegate[4 + i] = encodedActionUndelegate[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataUndelegate),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataUndelegate));

        // Mock the CoreWriter call
        bytes memory encodedActionWithdraw = abi.encode(weiAmount);
        bytes memory dataWithdraw = new bytes(4 + encodedActionWithdraw.length);
        dataWithdraw[0] = 0x01;
        dataWithdraw[1] = 0x00;
        dataWithdraw[2] = 0x00;
        dataWithdraw[3] = 0x05; // Staking withdraw action ID
        for (uint256 i = 0; i < encodedActionWithdraw.length; i++) {
            dataWithdraw[4 + i] = encodedActionWithdraw[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, dataWithdraw),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, dataWithdraw));

        vm.prank(manager);
        stakingVault.unstake(validator, weiAmount);

        // Verify lastDelegationChangeBlockNumber was updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_Unstake_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.unstake(validator, 1e8);
    }

    function test_Unstake_ZeroAmount() public {
        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.unstake(validator, 0);
    }

    function test_Unstake_InsufficientBalance() public {
        uint64 delegatedAmount = 50_000 * 1e8; // 50k HYPE delegated
        uint64 requestedAmount = 100_000 * 1e8; // 100k HYPE requested

        _mockDelegations(validator, delegatedAmount);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.unstake(validator, requestedAmount);
    }

    function test_Unstake_ValidatorNotFound() public {
        uint64 weiAmount = 1e8;

        // Mock empty delegations (validator not found)
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](0);
        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.unstake(validator, weiAmount);
    }

    function test_Unstake_StakeLockedUntilFuture() public {
        uint64 weiAmount = 1e8;
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(validator, weiAmount, futureTimestamp);

        vm.startPrank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVault.unstake(validator, weiAmount);
    }

    function test_Unstake_StakeUnlockedAtExactTimestamp() public {
        uint64 weiAmount = 1e8;
        uint64 currentTimestamp = uint64(block.timestamp); // Exact current timestamp

        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(validator, weiAmount, true);
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

        _mockDelegationsWithLock(validator, weiAmount, currentTimestamp);

        vm.prank(manager);
        stakingVault.unstake(validator, weiAmount);

        // Should succeed and update block number
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_Unstake_CannotCallTwiceInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(validator, weiAmount, true);
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

        _mockDelegations(validator, weiAmount);

        vm.startPrank(manager);
        stakingVault.unstake(validator, weiAmount);

        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.unstake(validator, weiAmount);
    }

    function test_Unstake_CannotCallAfterStakeInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock CoreWriter calls for tokenDelegate
        bytes memory delegateAction = abi.encode(validator, weiAmount, false);
        bytes memory delegateData = new bytes(4 + delegateAction.length);
        delegateData[0] = 0x01;
        delegateData[1] = 0x00;
        delegateData[2] = 0x00;
        delegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < delegateAction.length; i++) {
            delegateData[4 + i] = delegateAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, delegateData),
            abi.encode()
        );

        // Mock delegations for the validator so tokenUndelegate can try to undelegate from it
        _mockDelegations(validator, weiAmount);

        vm.startPrank(manager);

        // First call tokenDelegate on the validator
        stakingVault.stake(validator, weiAmount);

        // Now try to call tokenUndelegate on the same validator in the same block - should fail
        // because we can't read delegations for the validator in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.unstake(validator, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Token Redelegate                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TokenRedelegate_Success(uint64 weiAmount) public {
        vm.assume(weiAmount > 0);

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(validator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(validator2, weiAmount, false);
        bytes memory delegateData = new bytes(4 + delegateAction.length);
        delegateData[0] = 0x01;
        delegateData[1] = 0x00;
        delegateData[2] = 0x00;
        delegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < delegateAction.length; i++) {
            delegateData[4 + i] = delegateAction[i];
        }

        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, undelegateData),
            abi.encode()
        );
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, delegateData),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, undelegateData));
        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, delegateData));

        _mockDelegations(validator, weiAmount);

        vm.prank(manager);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);

        // Verify both validators' lastDelegationChangeBlockNumber were updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator2), block.number);
    }

    function test_TokenRedelegate_SameValidator() public {
        uint64 weiAmount = 1e8;

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.RedelegateToSameValidator.selector);
        stakingVault.tokenRedelegate(validator, validator, weiAmount);
    }

    function test_TokenRedelegate_ZeroAmount() public {
        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.tokenRedelegate(validator, validator2, 0);
    }

    function test_TokenRedelegate_InsufficientBalance() public {
        uint64 delegatedAmount = 50_000 * 1e8; // 50k HYPE delegated
        uint64 requestedAmount = 100_000 * 1e8; // 100k HYPE requested

        _mockDelegations(validator, delegatedAmount);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.tokenRedelegate(validator, validator2, requestedAmount);
    }

    function test_TokenRedelegate_ValidatorNotFound() public {
        address validator3 = makeAddr("validator3");
        uint64 weiAmount = 1e8;

        // Mock empty delegations (validator not found)
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](0);
        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.ValidatorNotWhitelisted.selector, validator3));
        stakingVault.tokenRedelegate(validator, validator3, weiAmount);
    }

    function test_TokenRedelegate_StakeLockedUntilFuture() public {
        uint64 weiAmount = 1e8;
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(validator, weiAmount, futureTimestamp);

        vm.startPrank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    function test_TokenRedelegate_StakeUnlockedAtExactTimestamp() public {
        uint64 weiAmount = 1e8;
        uint64 currentTimestamp = uint64(block.timestamp); // Exact current timestamp

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(validator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(validator2, weiAmount, false);
        bytes memory delegateData = new bytes(4 + delegateAction.length);
        delegateData[0] = 0x01;
        delegateData[1] = 0x00;
        delegateData[2] = 0x00;
        delegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < delegateAction.length; i++) {
            delegateData[4 + i] = delegateAction[i];
        }

        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, undelegateData),
            abi.encode()
        );
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, delegateData),
            abi.encode()
        );

        _mockDelegationsWithLock(validator, weiAmount, currentTimestamp);

        vm.prank(manager);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);

        // Should succeed and update block numbers for both validators
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator2), block.number);
    }

    function test_TokenRedelegate_NotManager(address notManager) public {
        vm.assume(notManager != manager);
        uint64 weiAmount = 1e8;

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    function test_TokenRedelegate_WhenPaused() public {
        uint64 weiAmount = 1e8;

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVault));

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVault)));
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    function test_TokenRedelegate_CannotCallTwiceInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(validator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(validator2, weiAmount, false);
        bytes memory delegateData = new bytes(4 + delegateAction.length);
        delegateData[0] = 0x01;
        delegateData[1] = 0x00;
        delegateData[2] = 0x00;
        delegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < delegateAction.length; i++) {
            delegateData[4 + i] = delegateAction[i];
        }

        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, undelegateData),
            abi.encode()
        );
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, delegateData),
            abi.encode()
        );

        _mockDelegations(validator, weiAmount);

        vm.startPrank(manager);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);

        // Second call in same block should fail during the tokenUndelegate call
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    function test_TokenRedelegate_CannotCallAfterTokenDelegateInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock CoreWriter calls for tokenDelegate
        bytes memory delegateAction = abi.encode(validator, weiAmount, false);
        bytes memory delegateData = new bytes(4 + delegateAction.length);
        delegateData[0] = 0x01;
        delegateData[1] = 0x00;
        delegateData[2] = 0x00;
        delegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < delegateAction.length; i++) {
            delegateData[4 + i] = delegateAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, delegateData),
            abi.encode()
        );

        // Mock delegations for validator1 so tokenRedelegate can try to undelegate from it
        _mockDelegations(validator, weiAmount);

        vm.startPrank(manager);

        // First call tokenDelegate on validator1
        stakingVault.stake(validator, weiAmount);

        // Now try to call tokenRedelegate FROM validator1 in the same block - should fail
        // because we can't read delegations for validator1 in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    function test_TokenRedelegate_CannotCallAfterTokenUndelegateInSameBlock() public {
        uint64 weiAmount = 1e8;

        // Mock CoreWriter calls for tokenUndelegate
        bytes memory undelegateAction = abi.encode(validator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, undelegateData),
            abi.encode()
        );

        _mockDelegations(validator, weiAmount);

        vm.startPrank(manager);

        // First call tokenUndelegate on validator1
        stakingVault.unstake(validator, weiAmount);

        // Now try to call tokenRedelegate FROM validator1 in the same block - should fail
        // because we can't read delegations for validator1 in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(validator, validator2, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Spot Send                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_SpotSend_Success(address destination, uint64 token, uint64 weiAmount) public {
        vm.assume(weiAmount > 0);

        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(destination, token, weiAmount);
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

        _mockCoreUserExists(destination, true);
        _mockSpotBalance(weiAmount);

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));

        vm.prank(manager);
        stakingVault.spotSend(destination, token, weiAmount);
    }

    function test_SpotSend_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        address destination = address(0x456);
        uint64 token = 0;
        uint64 weiAmount = 1e8;

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.spotSend(destination, token, weiAmount);
    }

    function test_SpotSend_ZeroAmount() public {
        address destination = address(0x456);
        uint64 token = 0;

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.spotSend(destination, token, 0);
    }

    function test_SpotSend_CoreUserDoesNotExist() public {
        address destination = address(0x456);
        uint64 token = 0;
        uint64 weiAmount = 1e8;

        _mockCoreUserExists(destination, false);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CoreUserDoesNotExist.selector, destination));
        stakingVault.spotSend(destination, token, weiAmount);
    }

    function test_SpotSend_InsufficientBalance() public {
        address destination = address(0x456);
        uint64 token = 0;
        uint64 weiAmount = 1e8;

        _mockCoreUserExists(destination, true);
        _mockSpotBalance(0);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.InsufficientHYPEBalance.selector));
        stakingVault.spotSend(destination, token, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Tests: Deposit                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Deposit_AsManager() public {
        uint256 amount = 1e18;
        vm.deal(manager, amount);

        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit IStakingVault.Deposit(manager, amount);
        stakingVault.deposit{value: amount}();

        assertEq(address(stakingVault).balance, amount);
    }

    function test_Deposit_CannotDepositInSameBlockAsTransfer() public {
        uint256 transferAmount = 1e18;
        uint256 depositAmount = 5e17;
        vm.deal(address(stakingVault), transferAmount);
        vm.deal(manager, depositAmount);

        vm.startPrank(manager);

        // First, make a transfer to core which updates lastEvmToCoreTransferBlockNumber
        stakingVault.transferHypeToCore(transferAmount);

        // Try to deposit in the same block - should fail
        vm.expectRevert(IStakingVault.CannotDepositUntilNextBlock.selector);
        stakingVault.deposit{value: depositAmount}();

        vm.stopPrank();
    }

    function test_Deposit_CanDepositWhenNoTransfersMade() public {
        uint256 amount = 1e18;
        vm.deal(manager, amount);

        // Initial state - no transfers made, lastEvmToCoreTransferBlockNumber is 0
        assertEq(stakingVault.lastEvmToCoreTransferBlockNumber(), 0);

        // Deposit should succeed since block.number > 0
        vm.prank(manager);
        stakingVault.deposit{value: amount}();

        assertEq(address(stakingVault).balance, amount);
    }

    function test_Deposit_CanDepositInNextBlockAfterTransfer() public {
        uint256 transferAmount = 1e18;
        uint256 depositAmount = 5e17;
        vm.deal(address(stakingVault), transferAmount);
        vm.deal(manager, depositAmount);

        vm.startPrank(manager);

        // First, make a transfer to core
        stakingVault.transferHypeToCore(transferAmount);

        // Move to next block
        vm.roll(block.number + 1);

        // Now deposit should succeed
        vm.expectEmit(true, true, true, true);
        emit IStakingVault.Deposit(manager, depositAmount);
        stakingVault.deposit{value: depositAmount}();

        assertEq(address(stakingVault).balance, depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_NotManager(address notManager) public {
        vm.assume(notManager != manager);
        uint256 amount = 1e18;
        vm.deal(notManager, amount);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.deposit{value: amount}();
        vm.stopPrank();
    }

    function test_Deposit_WhenPaused() public {
        uint256 amount = 1e18;
        vm.deal(manager, amount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVault));

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVault)));
        stakingVault.deposit{value: amount}();
        vm.stopPrank();
    }

    function test_Deposit_ZeroAmount() public {
        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.deposit{value: 0}();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                Tests: Transfer Hype To Core                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_TransferHypeToCore(uint256 amount) public {
        vm.assume(amount > 0);
        vm.deal(address(stakingVault), amount);
        uint256 vaultBalanceBefore = address(stakingVault).balance;
        uint256 systemAddressBalanceBefore = stakingVault.HYPE_SYSTEM_ADDRESS().balance;

        vm.prank(manager);
        stakingVault.transferHypeToCore(amount);

        assertEq(address(stakingVault).balance, vaultBalanceBefore - amount);
        assertEq(stakingVault.HYPE_SYSTEM_ADDRESS().balance, systemAddressBalanceBefore + amount);
        assertEq(stakingVault.lastEvmToCoreTransferBlockNumber(), block.number);
    }

    function test_TransferHypeToCore_UpdatesLastTransferBlockNumber() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount);

        // Initial state - lastEvmToCoreTransferBlockNumber should be 0
        assertEq(stakingVault.lastEvmToCoreTransferBlockNumber(), 0);

        vm.prank(manager);
        stakingVault.transferHypeToCore(amount);

        // Should update to current block number
        assertEq(stakingVault.lastEvmToCoreTransferBlockNumber(), block.number);
    }

    function test_TransferHypeToCore_CannotTransferInSameBlock() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount * 2);

        vm.startPrank(manager);

        // First transfer should succeed
        stakingVault.transferHypeToCore(amount);

        // Second transfer in same block should fail
        vm.expectRevert(IStakingVault.CannotTransferToCoreUntilNextBlock.selector);
        stakingVault.transferHypeToCore(amount);

        vm.stopPrank();
    }

    function test_TransferHypeToCore_CanTransferInNextBlock() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount * 2);

        vm.startPrank(manager);

        // First transfer
        stakingVault.transferHypeToCore(amount);
        uint256 firstTransferBlock = block.number;

        // Move to next block
        vm.roll(block.number + 1);

        // Second transfer should succeed
        stakingVault.transferHypeToCore(amount);

        // Verify both transfers succeeded and block number updated
        assertEq(address(stakingVault).balance, 0);
        assertEq(stakingVault.lastEvmToCoreTransferBlockNumber(), firstTransferBlock + 1);

        vm.stopPrank();
    }

    function test_TransferHypeToCore_ZeroAmount() public {
        uint256 vaultBalance = 1e18;
        vm.deal(address(stakingVault), vaultBalance);
        uint256 systemAddressBalanceBefore = stakingVault.HYPE_SYSTEM_ADDRESS().balance;

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.transferHypeToCore(0);

        assertEq(address(stakingVault).balance, vaultBalance);
        assertEq(stakingVault.HYPE_SYSTEM_ADDRESS().balance, systemAddressBalanceBefore);
    }

    function test_TransferHypeToCore_NotActivatedOnHyperCore() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount);

        // Mock the core user exists check to return false
        _mockCoreUserExists(address(stakingVault), false);

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStakingVault.CoreUserDoesNotExist.selector, address(stakingVault)));
        stakingVault.transferHypeToCore(amount);

        // Balance should remain unchanged
        assertEq(address(stakingVault).balance, amount);
    }

    function test_TransferHypeToCore_InsufficientBalance() public {
        uint256 vaultBalance = 1e18;
        uint256 transferAmount = 2e18; // More than vault balance
        vm.deal(address(stakingVault), vaultBalance);

        vm.prank(manager);
        vm.expectRevert(); // Should revert due to insufficient balance
        stakingVault.transferHypeToCore(transferAmount);
    }

    function test_TransferHypeToCore_NotManager(address notManager) public {
        vm.assume(notManager != manager);
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.transferHypeToCore(amount);

        // Balance should remain unchanged
        assertEq(address(stakingVault).balance, amount);
    }

    function test_TransferHypeToCore_WhenPaused() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVault));

        // Should revert when paused
        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVault)));
        stakingVault.transferHypeToCore(amount);

        // Balance should remain unchanged
        assertEq(address(stakingVault).balance, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Add API Wallet                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_AddApiWallet(address apiWalletAddress, string memory name) public {
        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(apiWalletAddress, name);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x09; // Add API wallet action ID
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, data),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));

        vm.prank(operator);
        stakingVault.addApiWallet(apiWalletAddress, name);
    }

    function test_AddApiWallet_EmptyName(address apiWalletAddress) public {
        string memory name = "";

        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(apiWalletAddress, name);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x09; // Add API wallet action ID
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        vm.mockCall(
            CoreWriterLibrary.CORE_WRITER,
            abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, data),
            abi.encode()
        );

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data));

        vm.prank(operator);
        stakingVault.addApiWallet(apiWalletAddress, name);
    }

    function test_AddApiWallet_NotOperator(address notOperator) public {
        vm.assume(notOperator != operator);

        address apiWalletAddress = address(0x789);
        string memory name = "TestWallet";

        vm.startPrank(notOperator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notOperator, roleRegistry.OPERATOR_ROLE()
            )
        );
        stakingVault.addApiWallet(apiWalletAddress, name);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Delegator Summary                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_DelegatorSummary() public {
        // Mock the L1Read call
        L1ReadLibrary.DelegatorSummary memory mockDelegatorSummary = L1ReadLibrary.DelegatorSummary({
            delegated: 1e18,
            undelegated: 0,
            totalPendingWithdrawal: 0,
            nPendingWithdrawals: 0
        });
        bytes memory encodedDelegatorSummary = abi.encode(mockDelegatorSummary);
        vm.mockCall(
            L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, // Precompile address
            abi.encode(address(stakingVault)), // Calldata parameters
            encodedDelegatorSummary // Return data
        );

        vm.expectCall(L1ReadLibrary.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)));

        L1ReadLibrary.DelegatorSummary memory result = stakingVault.delegatorSummary();
        assertEq(result.delegated, mockDelegatorSummary.delegated);
        assertEq(result.undelegated, mockDelegatorSummary.undelegated);
        assertEq(result.totalPendingWithdrawal, mockDelegatorSummary.totalPendingWithdrawal);
        assertEq(result.nPendingWithdrawals, mockDelegatorSummary.nPendingWithdrawals);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Spot Balance                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SpotBalance() public {
        // Mock the L1Read call
        L1ReadLibrary.SpotBalance memory mockSpotBalance =
            L1ReadLibrary.SpotBalance({total: 1e18, hold: 0, entryNtl: 0});
        bytes memory encodedSpotBalance = abi.encode(mockSpotBalance);
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS, // Precompile address
            abi.encode(address(stakingVault), 1), // Calldata parameters
            encodedSpotBalance // Return data
        );

        vm.expectCall(L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault), 1));

        L1ReadLibrary.SpotBalance memory result = stakingVault.spotBalance(1);
        assertEq(result.total, mockSpotBalance.total);
        assertEq(result.hold, mockSpotBalance.hold);
        assertEq(result.entryNtl, mockSpotBalance.entryNtl);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Pause                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_FunctionsWhenPaused() public {
        vm.prank(owner);
        roleRegistry.pause(address(stakingVault));

        vm.deal(address(stakingVault), 1e18);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.stake(validator, 1e10);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.unstake(validator, 1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.tokenRedelegate(address(0x123), address(0x456), 1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.transferHypeToCore(1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.spotSend(address(0x456), 0, 1e8);

        vm.prank(operator);
        vm.expectRevert();
        stakingVault.addApiWallet(address(0x789), "TestWallet");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              Tests: Receive and Fallback Functions         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_CannotReceive() public {
        uint256 amount = 1e18;
        uint256 balanceBefore = address(stakingVault).balance;

        address user = makeAddr("user");
        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(stakingVault).call{value: amount}("");

        assertFalse(success);
        assertEq(address(stakingVault).balance, balanceBefore);
    }

    function test_CannotFallback() public {
        uint256 amount = 1e18;
        uint256 balanceBefore = address(stakingVault).balance;

        address user = makeAddr("user");
        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(stakingVault).call{value: amount}("0x1234");

        assertFalse(success);
        assertEq(address(stakingVault).balance, balanceBefore);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Upgradeability                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_UpgradeToAndCall_OnlyOwner() public {
        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction(HYPE_TOKEN_ID);

        vm.prank(owner);
        stakingVault.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(stakingVault.roleRegistry()), address(roleRegistry));

        // Check that the extra function is available
        StakingVaultWithExtraFunction newProxy = StakingVaultWithExtraFunction(payable(address(stakingVault)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction(HYPE_TOKEN_ID);

        vm.startPrank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        stakingVault.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        StakingVaultWithExtraFunction newProxy = StakingVaultWithExtraFunction(payable(address(stakingVault)));
        vm.expectRevert();
        newProxy.extraFunction();
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
        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction(HYPE_TOKEN_ID);
        vm.prank(newOwner);
        stakingVault.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(stakingVault.roleRegistry()), address(roleRegistry));

        // Check that the extra function is available
        StakingVaultWithExtraFunction newProxy = StakingVaultWithExtraFunction(payable(address(stakingVault)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        StakingVaultWithExtraFunction anotherImplementation = new StakingVaultWithExtraFunction(HYPE_TOKEN_ID);
        vm.startPrank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        stakingVault.upgradeToAndCall(address(anotherImplementation), "");
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

    /// @dev Helper function to mock spot balance for testing staking deposit calls
    /// @param total The total balance to mock (in 8 decimals)
    function _mockSpotBalance(uint64 total) internal {
        vm.mockCall(
            L1ReadLibrary.SPOT_BALANCE_PRECOMPILE_ADDRESS,
            abi.encode(address(stakingVault), HYPE_TOKEN_ID),
            abi.encode(L1ReadLibrary.SpotBalance({total: total, hold: 0, entryNtl: 0}))
        );
    }

    function _mockDelegations(address _validator, uint64 weiAmount) internal {
        _mockDelegationsWithLock(_validator, weiAmount, 0);
    }

    function _mockDelegationsWithLock(address _validator, uint64 weiAmount, uint64 lockedUntilTimestamp) internal {
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](1);
        mockDelegations[0] = L1ReadLibrary.Delegation({
            validator: _validator,
            amount: weiAmount,
            lockedUntilTimestamp: lockedUntilTimestamp
        });

        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);
    }
}

contract StakingVaultWithExtraFunction is StakingVault {
    constructor(uint64 hypeTokenId) StakingVault(hypeTokenId) {}

    function extraFunction() public pure returns (bool) {
        return true;
    }
}
