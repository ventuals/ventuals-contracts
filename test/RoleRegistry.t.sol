// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";

contract RoleRegistryTest is Test {
    RoleRegistry roleRegistry;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");
    address public contractToTest = makeAddr("contractToTest");

    function setUp() public {
        RoleRegistry implementation = new RoleRegistry();
        bytes memory initData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        roleRegistry = RoleRegistry(address(proxy));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Initialization                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize_OwnerAndAdmin() public view {
        assertEq(roleRegistry.owner(), owner);
        assertTrue(roleRegistry.hasRole(roleRegistry.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_Initialize_CannotInitializeTwice() public {
        vm.expectRevert();
        roleRegistry.initialize(owner);
    }

    function test_Initialize_DefaultPauseState(address fuzzContract) public view {
        assertFalse(roleRegistry.isPaused(fuzzContract));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Grant/Revoke Role                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GrantRole_OnlyOwner(bytes32 role) public {
        vm.startPrank(owner);
        roleRegistry.grantRole(role, manager);
        assertTrue(roleRegistry.hasRole(role, manager));
    }

    function test_GrantRole_NotOwner(bytes32 role, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        roleRegistry.grantRole(role, manager);
    }

    function test_RevokeRole_OnlyOwner(bytes32 role) public {
        vm.startPrank(owner);
        roleRegistry.grantRole(role, manager);
        assertTrue(roleRegistry.hasRole(role, manager));

        roleRegistry.revokeRole(role, manager);
        assertFalse(roleRegistry.hasRole(role, manager));
    }

    function test_RevokeRole_NotOwner(bytes32 role, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(owner);
        roleRegistry.grantRole(role, manager);
        assertTrue(roleRegistry.hasRole(role, manager));

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        roleRegistry.revokeRole(role, manager);
        assertTrue(roleRegistry.hasRole(role, manager));
    }

    function test_GrantAndRevokeRole(bytes32 role, address fuzzUser) public {
        vm.assume(!roleRegistry.hasRole(role, fuzzUser));

        vm.startPrank(owner);
        roleRegistry.grantRole(role, fuzzUser);
        assertTrue(roleRegistry.hasRole(role, fuzzUser));

        vm.startPrank(owner);
        roleRegistry.revokeRole(role, fuzzUser);
        assertFalse(roleRegistry.hasRole(role, fuzzUser));
    }

    function test_GrantRole_SameUserMultipleRoles(bytes32 role1, bytes32 role2, address fuzzUser) public {
        vm.assume(role1 != role2);

        vm.startPrank(owner);
        roleRegistry.grantRole(role1, fuzzUser);
        roleRegistry.grantRole(role2, fuzzUser);

        assertTrue(roleRegistry.hasRole(role1, fuzzUser));
        assertTrue(roleRegistry.hasRole(role2, fuzzUser));
    }

    function test_RevokeRole_OneOfMultiple(bytes32 role1, bytes32 role2, address fuzzUser) public {
        vm.assume(role1 != role2);

        vm.startPrank(owner);
        roleRegistry.grantRole(role1, fuzzUser);
        roleRegistry.grantRole(role2, fuzzUser);

        roleRegistry.revokeRole(role1, fuzzUser);

        assertFalse(roleRegistry.hasRole(role1, fuzzUser));
        assertTrue(roleRegistry.hasRole(role2, fuzzUser));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   Tests: Pause/Unpause                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Pause_OnlyOwner(address fuzzContract) public {
        vm.startPrank(owner);
        assertFalse(roleRegistry.isPaused(fuzzContract));
        roleRegistry.pause(fuzzContract);
        assertTrue(roleRegistry.isPaused(fuzzContract));
    }

    function test_Pause_NotOwner(address fuzzContract, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        roleRegistry.pause(fuzzContract);
        assertFalse(roleRegistry.isPaused(fuzzContract));
    }

    function test_Unpause_OnlyOwner(address fuzzContract) public {
        vm.startPrank(owner);
        roleRegistry.pause(fuzzContract);
        assertTrue(roleRegistry.isPaused(fuzzContract));
        roleRegistry.unpause(fuzzContract);
        assertFalse(roleRegistry.isPaused(contractToTest));
    }

    function test_Unpause_NotOwner(address fuzzContract, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(owner);
        roleRegistry.pause(fuzzContract);
        assertTrue(roleRegistry.isPaused(fuzzContract));

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        roleRegistry.unpause(fuzzContract);
    }

    function test_PauseAndUnpause(address fuzzContract) public {
        vm.startPrank(owner);
        roleRegistry.pause(fuzzContract);
        assertTrue(roleRegistry.isPaused(fuzzContract));
        roleRegistry.unpause(fuzzContract);
        assertFalse(roleRegistry.isPaused(fuzzContract));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Upgradeability                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        RoleRegistryWithExtraFunction newImplementation = new RoleRegistryWithExtraFunction();

        vm.startPrank(owner);
        roleRegistry.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Verify upgrade was successful by checking that it's still functional
        assertTrue(roleRegistry.hasRole(roleRegistry.DEFAULT_ADMIN_ROLE(), owner));

        // Check that the extra function is available
        RoleRegistryWithExtraFunction newProxy = RoleRegistryWithExtraFunction(address(roleRegistry));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner() public {
        RoleRegistryWithExtraFunction newImplementation = new RoleRegistryWithExtraFunction();

        vm.startPrank(user);
        vm.expectRevert();
        roleRegistry.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        RoleRegistryWithExtraFunction newProxy = RoleRegistryWithExtraFunction(address(roleRegistry));
        vm.expectRevert();
        newProxy.extraFunction();
    }

    function test_UpgradeToAndCall_WithData() public {
        RoleRegistryWithExtraFunction newImplementation = new RoleRegistryWithExtraFunction();
        bytes memory initData = abi.encodeWithSelector(RoleRegistry.grantRole.selector, MANAGER_ROLE, manager);

        vm.startPrank(owner);
        roleRegistry.upgradeToAndCall(address(newImplementation), initData);

        // Verify upgrade was successful and data was executed
        assertTrue(roleRegistry.hasRole(roleRegistry.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(roleRegistry.hasRole(MANAGER_ROLE, manager));

        // Check that the extra function is available
        RoleRegistryWithExtraFunction newProxy = RoleRegistryWithExtraFunction(address(roleRegistry));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwnerWithData() public {
        RoleRegistryWithExtraFunction newImplementation = new RoleRegistryWithExtraFunction();
        bytes memory initData = abi.encodeWithSelector(RoleRegistry.grantRole.selector, MANAGER_ROLE, manager);

        vm.startPrank(user);
        vm.expectRevert();
        roleRegistry.upgradeToAndCall(address(newImplementation), initData);

        // Check that the extra function is not available
        RoleRegistryWithExtraFunction newProxy = RoleRegistryWithExtraFunction(address(roleRegistry));
        vm.expectRevert();
        newProxy.extraFunction();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: TransferOwnership                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TransferOwnership_OnlyOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        roleRegistry.transferOwnership(newOwner);
        vm.stopPrank();

        // Check that pendingOwner is set but owner hasn't changed yet
        assertEq(roleRegistry.pendingOwner(), newOwner);
        assertEq(roleRegistry.owner(), owner);

        // New owner accepts ownership
        vm.startPrank(newOwner);
        roleRegistry.acceptOwnership();
        vm.stopPrank();

        // Check that ownership has transferred
        assertEq(roleRegistry.owner(), newOwner);
        assertEq(roleRegistry.pendingOwner(), address(0));
    }

    function test_TransferOwnership_NotOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(user);
        vm.expectRevert();
        roleRegistry.transferOwnership(newOwner);
        vm.stopPrank();
    }

    function test_AcceptOwnership_OnlyPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        roleRegistry.transferOwnership(newOwner);
        vm.stopPrank();

        // Try to accept ownership from wrong account
        vm.startPrank(user);
        vm.expectRevert();
        roleRegistry.acceptOwnership();
        vm.stopPrank();

        // Correct account accepts ownership
        vm.startPrank(newOwner);
        roleRegistry.acceptOwnership();
        vm.stopPrank();

        assertEq(roleRegistry.owner(), newOwner);
    }

    function test_RenounceOwnership_OnlyOwner() public {
        vm.startPrank(owner);
        roleRegistry.renounceOwnership();
        assertEq(roleRegistry.owner(), address(0));
    }

    function test_RenounceOwnership_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        roleRegistry.renounceOwnership();
    }
}

contract RoleRegistryWithExtraFunction is RoleRegistry {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
