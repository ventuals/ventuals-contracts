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

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public operator = makeAddr("operator");

    function setUp() public {
        RoleRegistry roleRegistryImplementation = new RoleRegistry();
        bytes memory roleRegistryInitData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);
        ERC1967Proxy roleRegistryProxy = new ERC1967Proxy(address(roleRegistryImplementation), roleRegistryInitData);
        roleRegistry = RoleRegistry(address(roleRegistryProxy));

        StakingVault stakingVaultImplementation = new StakingVault();
        bytes memory stakingVaultInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(roleRegistryProxy));
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImplementation), stakingVaultInitData);
        stakingVault = StakingVault(payable(stakingVaultProxy));

        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), manager);
        roleRegistry.grantRole(roleRegistry.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        // Mock the core user exists check to return true
        _mockCoreUserExists(true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Staking Deposit                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_StakingDeposit(uint64 weiAmount) public {
        vm.assume(weiAmount < type(uint64).max);

        // Mock the CoreWriter call
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

        vm.prank(manager);
        stakingVault.stakingDeposit(weiAmount);
    }

    function test_StakingDeposit_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        vm.deal(notManager, 1e18);
        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.stakingDeposit(1e10);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Staking Withdraw                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_StakingWithdraw(uint64 weiAmount) public {
        // Mock the CoreWriter call
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

        vm.prank(manager);
        stakingVault.stakingWithdraw(weiAmount);
    }

    function test_StakingWithdraw_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.stakingWithdraw(1e8);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Token Delegate                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_TokenDelegate(address validator, uint64 weiAmount) public {
        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(validator, weiAmount, false);
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

        vm.prank(manager);
        stakingVault.tokenDelegate(validator, weiAmount);

        // Verify lastDelegationChangeBlockNumber was updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_TokenDelegate_CanCallInSameBlock() public {
        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;

        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(validator, weiAmount, false);
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

        vm.expectCall(CoreWriterLibrary.CORE_WRITER, abi.encodeCall(ICoreWriter.sendRawAction, data), 2);

        vm.startPrank(manager);
        stakingVault.tokenDelegate(validator, weiAmount);
        stakingVault.tokenDelegate(validator, weiAmount);
    }

    function test_TokenDelegate_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.tokenDelegate(validator, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Token Undelegate                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TokenUndelegate(address validator, uint64 weiAmount) public {
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

        vm.prank(manager);
        stakingVault.tokenUndelegate(validator, weiAmount);

        // Verify lastDelegationChangeBlockNumber was updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_TokenUndelegate_InsufficientBalance() public {
        address validator = makeAddr("validator");
        uint64 delegatedAmount = 50_000 * 1e8; // 50k HYPE delegated
        uint64 requestedAmount = 100_000 * 1e8; // 100k HYPE requested

        _mockDelegations(validator, delegatedAmount);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.tokenUndelegate(validator, requestedAmount);
    }

    function test_TokenUndelegate_ValidatorNotFound() public {
        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;

        // Mock empty delegations (validator not found)
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](0);
        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.tokenUndelegate(validator, weiAmount);
    }

    function test_TokenUndelegate_StakeLockedUntilFuture() public {
        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(validator, weiAmount, futureTimestamp);

        vm.startPrank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, validator, futureTimestamp)
        );
        stakingVault.tokenUndelegate(validator, weiAmount);
    }

    function test_TokenUndelegate_StakeUnlockedAtExactTimestamp() public {
        address validator = makeAddr("validator");
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
        stakingVault.tokenUndelegate(validator, weiAmount);

        // Should succeed and update block number
        assertEq(stakingVault.lastDelegationChangeBlockNumber(validator), block.number);
    }

    function test_TokenUndelegate_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.tokenUndelegate(validator, weiAmount);
    }

    function test_TokenUndelegate_CannotCallTwiceInSameBlock() public {
        address validator = makeAddr("validator");
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
        stakingVault.tokenUndelegate(validator, weiAmount);

        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenUndelegate(validator, weiAmount);
    }

    function test_TokenUndelegate_CannotCallAfterTokenDelegateInSameBlock() public {
        address validator = makeAddr("validator");
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
        stakingVault.tokenDelegate(validator, weiAmount);

        // Now try to call tokenUndelegate on the same validator in the same block - should fail
        // because we can't read delegations for the validator in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenUndelegate(validator, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Token Redelegate                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TokenRedelegate(address fromValidator, address toValidator, uint64 weiAmount) public {
        vm.assume(fromValidator != toValidator);
        vm.assume(weiAmount > 0);

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(fromValidator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(toValidator, weiAmount, false);
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

        _mockDelegations(fromValidator, weiAmount);

        vm.prank(manager);
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);

        // Verify both validators' lastDelegationChangeBlockNumber were updated
        assertEq(stakingVault.lastDelegationChangeBlockNumber(fromValidator), block.number);
        assertEq(stakingVault.lastDelegationChangeBlockNumber(toValidator), block.number);
    }

    function test_TokenRedelegate_SameValidator() public {
        address validator = makeAddr("validator");
        uint64 weiAmount = 1e8;

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.RedelegateToSameValidator.selector);
        stakingVault.tokenRedelegate(validator, validator, weiAmount);
    }

    function test_TokenRedelegate_ZeroAmount() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.ZeroAmount.selector);
        stakingVault.tokenRedelegate(fromValidator, toValidator, 0);
    }

    function test_TokenRedelegate_InsufficientBalance() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 delegatedAmount = 50_000 * 1e8; // 50k HYPE delegated
        uint64 requestedAmount = 100_000 * 1e8; // 100k HYPE requested

        _mockDelegations(fromValidator, delegatedAmount);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.tokenRedelegate(fromValidator, toValidator, requestedAmount);
    }

    function test_TokenRedelegate_ValidatorNotFound() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;

        // Mock empty delegations (validator not found)
        L1ReadLibrary.Delegation[] memory mockDelegations = new L1ReadLibrary.Delegation[](0);
        bytes memory encodedDelegations = abi.encode(mockDelegations);
        vm.mockCall(L1ReadLibrary.DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedDelegations);

        vm.startPrank(manager);
        vm.expectRevert(IStakingVault.InsufficientHYPEBalance.selector);
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);
    }

    function test_TokenRedelegate_StakeLockedUntilFuture() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;
        uint64 futureTimestamp = uint64(block.timestamp + 1000); // 1000 seconds in the future

        _mockDelegationsWithLock(fromValidator, weiAmount, futureTimestamp);

        vm.startPrank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingVault.StakeLockedUntilTimestamp.selector, fromValidator, futureTimestamp)
        );
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);
    }

    function test_TokenRedelegate_StakeUnlockedAtExactTimestamp() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;
        uint64 currentTimestamp = uint64(block.timestamp); // Exact current timestamp

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(fromValidator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(toValidator, weiAmount, false);
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

        _mockDelegationsWithLock(fromValidator, weiAmount, currentTimestamp);

        vm.prank(manager);
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);

        // Should succeed and update block numbers for both validators
        assertEq(stakingVault.lastDelegationChangeBlockNumber(fromValidator), block.number);
        assertEq(stakingVault.lastDelegationChangeBlockNumber(toValidator), block.number);
    }

    function test_TokenRedelegate_NotManager(address notManager) public {
        vm.assume(notManager != manager);

        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);
    }

    function test_TokenRedelegate_WhenPaused() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(stakingVault));

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Base.Paused.selector, address(stakingVault)));
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);
    }

    function test_TokenRedelegate_CannotCallTwiceInSameBlock() public {
        address fromValidator = makeAddr("fromValidator");
        address toValidator = makeAddr("toValidator");
        uint64 weiAmount = 1e8;

        // Mock the CoreWriter calls for both undelegate and delegate
        bytes memory undelegateAction = abi.encode(fromValidator, weiAmount, true);
        bytes memory undelegateData = new bytes(4 + undelegateAction.length);
        undelegateData[0] = 0x01;
        undelegateData[1] = 0x00;
        undelegateData[2] = 0x00;
        undelegateData[3] = 0x03; // Token delegate action ID
        for (uint256 i = 0; i < undelegateAction.length; i++) {
            undelegateData[4 + i] = undelegateAction[i];
        }

        bytes memory delegateAction = abi.encode(toValidator, weiAmount, false);
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

        _mockDelegations(fromValidator, weiAmount);

        vm.startPrank(manager);
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);

        // Second call in same block should fail during the tokenUndelegate call
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(fromValidator, toValidator, weiAmount);
    }

    function test_TokenRedelegate_CannotCallAfterTokenDelegateInSameBlock() public {
        address validator1 = makeAddr("validator1");
        address validator2 = makeAddr("validator2");
        uint64 weiAmount = 1e8;

        // Mock CoreWriter calls for tokenDelegate
        bytes memory delegateAction = abi.encode(validator1, weiAmount, false);
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
        _mockDelegations(validator1, weiAmount);

        vm.startPrank(manager);

        // First call tokenDelegate on validator1
        stakingVault.tokenDelegate(validator1, weiAmount);

        // Now try to call tokenRedelegate FROM validator1 in the same block - should fail
        // because we can't read delegations for validator1 in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(validator1, validator2, weiAmount);
    }

    function test_TokenRedelegate_CannotCallAfterTokenUndelegateInSameBlock() public {
        address validator1 = makeAddr("validator1");
        address validator2 = makeAddr("validator2");
        uint64 weiAmount = 1e8;

        // Mock CoreWriter calls for tokenUndelegate
        bytes memory undelegateAction = abi.encode(validator1, weiAmount, true);
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

        _mockDelegations(validator1, weiAmount);

        vm.startPrank(manager);

        // First call tokenUndelegate on validator1
        stakingVault.tokenUndelegate(validator1, weiAmount);

        // Now try to call tokenRedelegate FROM validator1 in the same block - should fail
        // because we can't read delegations for validator1 in the same block
        vm.expectRevert(IStakingVault.CannotReadDelegationUntilNextBlock.selector);
        stakingVault.tokenRedelegate(validator1, validator2, weiAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Spot Send                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_SpotSend(address destination, uint64 token, uint64 weiAmount) public {
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                Tests: Transfer Hype To Core                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_TransferHypeToCore(uint256 amount) public {
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

        vm.prank(manager);
        stakingVault.transferHypeToCore(0);

        assertEq(address(stakingVault).balance, vaultBalance);
        assertEq(stakingVault.HYPE_SYSTEM_ADDRESS().balance, systemAddressBalanceBefore);
    }

    function test_TransferHypeToCore_NotActivatedOnHyperCore() public {
        uint256 amount = 1e18;
        vm.deal(address(stakingVault), amount);

        // Mock the core user exists check to return false
        _mockCoreUserExists(false);

        vm.prank(manager);
        vm.expectRevert(IStakingVault.NotActivatedOnHyperCore.selector);
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
        stakingVault.stakingDeposit(1e10);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.stakingWithdraw(1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.tokenDelegate(address(0x123), 1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.tokenUndelegate(address(0x123), 1e8);

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
        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction();

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

        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction();

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
        StakingVaultWithExtraFunction newImplementation = new StakingVaultWithExtraFunction();
        vm.prank(newOwner);
        stakingVault.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(stakingVault.roleRegistry()), address(roleRegistry));

        // Check that the extra function is available
        StakingVaultWithExtraFunction newProxy = StakingVaultWithExtraFunction(payable(address(stakingVault)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        StakingVaultWithExtraFunction anotherImplementation = new StakingVaultWithExtraFunction();
        vm.startPrank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        stakingVault.upgradeToAndCall(address(anotherImplementation), "");
    }

    /// @dev Helper function to mock the core user exists check
    /// @param exists Whether the core user should exist on HyperCore
    function _mockCoreUserExists(bool exists) internal {
        L1ReadLibrary.CoreUserExists memory mockCoreUserExists = L1ReadLibrary.CoreUserExists({exists: exists});
        bytes memory encodedCoreUserExists = abi.encode(mockCoreUserExists);
        vm.mockCall(
            L1ReadLibrary.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, abi.encode(address(stakingVault)), encodedCoreUserExists
        );
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
}

contract StakingVaultWithExtraFunction is StakingVault {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
