// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

contract ProtocolRegistryTest is Test {
    ProtocolRegistry protocolRegistry;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");
    address public contractToTest = makeAddr("contractToTest");

    function setUp() public {
        ProtocolRegistry implementation = new ProtocolRegistry();
        bytes memory initData = abi.encodeWithSelector(ProtocolRegistry.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        protocolRegistry = ProtocolRegistry(address(proxy));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  Tests: Initialization                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize_OwnerAndAdmin() public view {
        assertEq(protocolRegistry.owner(), owner);
        assertTrue(protocolRegistry.hasRole(protocolRegistry.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_Initialize_CannotInitializeTwice() public {
        vm.expectRevert();
        protocolRegistry.initialize(owner);
    }

    function test_Initialize_DefaultPauseState(address fuzzContract) public view {
        assertFalse(protocolRegistry.isPaused(fuzzContract));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Grant/Revoke Role                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_GrantRole_OnlyOwner(bytes32 role) public {
        vm.startPrank(owner);
        protocolRegistry.grantRole(role, manager);
        assertTrue(protocolRegistry.hasRole(role, manager));
    }

    function test_GrantRole_NotOwner(bytes32 role, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        protocolRegistry.grantRole(role, manager);
    }

    function test_RevokeRole_OnlyOwner(bytes32 role) public {
        vm.startPrank(owner);
        protocolRegistry.grantRole(role, manager);
        assertTrue(protocolRegistry.hasRole(role, manager));

        protocolRegistry.revokeRole(role, manager);
        assertFalse(protocolRegistry.hasRole(role, manager));
    }

    function test_RevokeRole_NotOwner(bytes32 role, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(owner);
        protocolRegistry.grantRole(role, manager);
        assertTrue(protocolRegistry.hasRole(role, manager));

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        protocolRegistry.revokeRole(role, manager);
        assertTrue(protocolRegistry.hasRole(role, manager));
    }

    function test_GrantAndRevokeRole(bytes32 role, address fuzzUser) public {
        vm.assume(!protocolRegistry.hasRole(role, fuzzUser));

        vm.startPrank(owner);
        protocolRegistry.grantRole(role, fuzzUser);
        assertTrue(protocolRegistry.hasRole(role, fuzzUser));

        vm.startPrank(owner);
        protocolRegistry.revokeRole(role, fuzzUser);
        assertFalse(protocolRegistry.hasRole(role, fuzzUser));
    }

    function test_GrantRole_SameUserMultipleRoles(bytes32 role1, bytes32 role2, address fuzzUser) public {
        vm.assume(role1 != role2);

        vm.startPrank(owner);
        protocolRegistry.grantRole(role1, fuzzUser);
        protocolRegistry.grantRole(role2, fuzzUser);

        assertTrue(protocolRegistry.hasRole(role1, fuzzUser));
        assertTrue(protocolRegistry.hasRole(role2, fuzzUser));
    }

    function test_RevokeRole_OneOfMultiple(bytes32 role1, bytes32 role2, address fuzzUser) public {
        vm.assume(role1 != role2);

        vm.startPrank(owner);
        protocolRegistry.grantRole(role1, fuzzUser);
        protocolRegistry.grantRole(role2, fuzzUser);

        protocolRegistry.revokeRole(role1, fuzzUser);

        assertFalse(protocolRegistry.hasRole(role1, fuzzUser));
        assertTrue(protocolRegistry.hasRole(role2, fuzzUser));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   Tests: Pause/Unpause                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Pause_OnlyOwner(address fuzzContract) public {
        vm.startPrank(owner);
        assertFalse(protocolRegistry.isPaused(fuzzContract));
        protocolRegistry.pause(fuzzContract);
        assertTrue(protocolRegistry.isPaused(fuzzContract));
    }

    function test_Pause_NotOwner(address fuzzContract, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        protocolRegistry.pause(fuzzContract);
        assertFalse(protocolRegistry.isPaused(fuzzContract));
    }

    function test_Unpause_OnlyOwner(address fuzzContract) public {
        vm.startPrank(owner);
        protocolRegistry.pause(fuzzContract);
        assertTrue(protocolRegistry.isPaused(fuzzContract));
        protocolRegistry.unpause(fuzzContract);
        assertFalse(protocolRegistry.isPaused(contractToTest));
    }

    function test_Unpause_NotOwner(address fuzzContract, address fuzzUser) public {
        vm.assume(fuzzUser != owner);

        vm.startPrank(owner);
        protocolRegistry.pause(fuzzContract);
        assertTrue(protocolRegistry.isPaused(fuzzContract));

        vm.startPrank(fuzzUser);
        vm.expectRevert();
        protocolRegistry.unpause(fuzzContract);
    }

    function test_PauseAndUnpause(address fuzzContract) public {
        vm.startPrank(owner);
        protocolRegistry.pause(fuzzContract);
        assertTrue(protocolRegistry.isPaused(fuzzContract));
        protocolRegistry.unpause(fuzzContract);
        assertFalse(protocolRegistry.isPaused(fuzzContract));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Upgradeability                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_UpgradeToAndCall_OnlyOwner() public {
        ProtocolRegistryWithExtraFunction newImplementation = new ProtocolRegistryWithExtraFunction();

        vm.startPrank(owner);
        protocolRegistry.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Verify upgrade was successful by checking that it's still functional
        assertTrue(protocolRegistry.hasRole(protocolRegistry.DEFAULT_ADMIN_ROLE(), owner));

        // Check that the extra function is available
        ProtocolRegistryWithExtraFunction newProxy = ProtocolRegistryWithExtraFunction(address(protocolRegistry));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner() public {
        ProtocolRegistryWithExtraFunction newImplementation = new ProtocolRegistryWithExtraFunction();

        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        ProtocolRegistryWithExtraFunction newProxy = ProtocolRegistryWithExtraFunction(address(protocolRegistry));
        vm.expectRevert();
        newProxy.extraFunction();
    }

    function test_UpgradeToAndCall_WithData() public {
        ProtocolRegistryWithExtraFunction newImplementation = new ProtocolRegistryWithExtraFunction();
        bytes memory initData = abi.encodeWithSelector(ProtocolRegistry.grantRole.selector, MANAGER_ROLE, manager);

        vm.startPrank(owner);
        protocolRegistry.upgradeToAndCall(address(newImplementation), initData);

        // Verify upgrade was successful and data was executed
        assertTrue(protocolRegistry.hasRole(protocolRegistry.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(protocolRegistry.hasRole(MANAGER_ROLE, manager));

        // Check that the extra function is available
        ProtocolRegistryWithExtraFunction newProxy = ProtocolRegistryWithExtraFunction(address(protocolRegistry));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwnerWithData() public {
        ProtocolRegistryWithExtraFunction newImplementation = new ProtocolRegistryWithExtraFunction();
        bytes memory initData = abi.encodeWithSelector(ProtocolRegistry.grantRole.selector, MANAGER_ROLE, manager);

        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.upgradeToAndCall(address(newImplementation), initData);

        // Check that the extra function is not available
        ProtocolRegistryWithExtraFunction newProxy = ProtocolRegistryWithExtraFunction(address(protocolRegistry));
        vm.expectRevert();
        newProxy.extraFunction();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: TransferOwnership                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_TransferOwnership_OnlyOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        protocolRegistry.transferOwnership(newOwner);
        vm.stopPrank();

        // Check that pendingOwner is set but owner hasn't changed yet
        assertEq(protocolRegistry.pendingOwner(), newOwner);
        assertEq(protocolRegistry.owner(), owner);

        // New owner accepts ownership
        vm.startPrank(newOwner);
        protocolRegistry.acceptOwnership();
        vm.stopPrank();

        // Check that ownership has transferred
        assertEq(protocolRegistry.owner(), newOwner);
        assertEq(protocolRegistry.pendingOwner(), address(0));
    }

    function test_TransferOwnership_NotOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.transferOwnership(newOwner);
        vm.stopPrank();
    }

    function test_AcceptOwnership_OnlyPendingOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.startPrank(owner);
        protocolRegistry.transferOwnership(newOwner);
        vm.stopPrank();

        // Try to accept ownership from wrong account
        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.acceptOwnership();
        vm.stopPrank();

        // Correct account accepts ownership
        vm.startPrank(newOwner);
        protocolRegistry.acceptOwnership();
        vm.stopPrank();

        assertEq(protocolRegistry.owner(), newOwner);
    }

    function test_RenounceOwnership_OnlyOwner() public {
        vm.startPrank(owner);
        protocolRegistry.renounceOwnership();
        assertEq(protocolRegistry.owner(), address(0));
    }

    function test_RenounceOwnership_NotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.renounceOwnership();
    }
}

contract ProtocolRegistryWithExtraFunction is ProtocolRegistry {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
