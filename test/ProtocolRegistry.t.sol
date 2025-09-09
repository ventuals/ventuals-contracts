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

    function test_AuthorizeUpgrade_OnlyOwner() public {
        address newImplementation = address(0x999);

        vm.startPrank(user);
        vm.expectRevert();
        protocolRegistry.upgradeToAndCall(newImplementation, "");
    }
}
