// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {vHYPE} from "../src/vHYPE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

contract vHYPETest is Test {
    ProtocolRegistry protocolRegistry;
    vHYPE public token;

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");

    function setUp() public {
        ProtocolRegistry protocolRegistryImplementation = new ProtocolRegistry();
        bytes memory protocolRegistryInitData = abi.encodeWithSelector(ProtocolRegistry.initialize.selector, owner);
        ERC1967Proxy protocolRegistryProxy =
            new ERC1967Proxy(address(protocolRegistryImplementation), protocolRegistryInitData);
        protocolRegistry = ProtocolRegistry(address(protocolRegistryProxy));

        vHYPE implementation = new vHYPE();
        bytes memory initData = abi.encodeWithSelector(vHYPE.initialize.selector, address(protocolRegistryProxy));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = vHYPE(address(proxy));

        vm.startPrank(owner);
        protocolRegistry.grantRole(protocolRegistry.MANAGER_ROLE(), manager);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Mint                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Mint_OnlyManager(address user, uint256 amount) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);

        vm.prank(manager);
        token.mint(user, amount);
        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_Mint_NotManager(address user, uint256 amount) public {
        vm.assume(user != address(0));
        vm.assume(user != manager);
        vm.assume(amount > 0);

        vm.prank(user);
        vm.expectRevert();
        token.mint(user, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Burn                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_CanBurnOwnTokens(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);

        vm.prank(manager);
        token.mint(user, amount);

        vm.prank(user);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user), amount - burnAmount);
        assertEq(token.totalSupply(), amount - burnAmount);
    }

    function test_CanBurnWithApproval(address user1, address user2, uint256 amount, uint256 burnAmount) public {
        vm.assume(user1 != address(0));
        vm.assume(user2 != address(0));
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);

        vm.prank(manager);
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, burnAmount);

        vm.prank(user2);
        token.burnFrom(user1, burnAmount);

        assertEq(token.balanceOf(user1), amount - burnAmount);
        assertEq(token.totalSupply(), amount - burnAmount);
        assertEq(token.allowance(user1, user2), 0);
    }

    function test_CannotBurnMoreThanBalance(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);
        vm.assume(burnAmount > amount);

        vm.prank(manager);
        token.mint(user, amount);

        vm.prank(user);
        vm.expectRevert();
        token.burn(burnAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Transfer                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Transfer(uint256 amount, uint256 transferAmount) public {
        vm.assume(amount > 0);
        vm.assume(amount > transferAmount);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.prank(manager);
        token.mint(user1, amount);

        vm.prank(user1);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user1), amount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
    }

    function test_ApproveAndTransferFrom(uint256 amount, uint256 transferAmount) public {
        vm.assume(amount > 0);
        vm.assume(amount > transferAmount);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.prank(manager);
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, transferAmount);

        vm.prank(user2);
        token.transferFrom(user1, user2, transferAmount);

        assertEq(token.balanceOf(user1), amount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.allowance(user1, user2), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Upgradeability                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_UpgradeToAndCall_OnlyOwner() public {
        vHYPEWithExtraFunction newImplementation = new vHYPEWithExtraFunction();

        vm.prank(owner);
        token.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(token.protocolRegistry()), address(protocolRegistry));

        // Check that the extra function is available
        vHYPEWithExtraFunction newProxy = vHYPEWithExtraFunction(payable(address(token)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        vHYPEWithExtraFunction newImplementation = new vHYPEWithExtraFunction();

        vm.prank(notOwner);
        vm.expectRevert("Caller is not the owner");
        token.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        vHYPEWithExtraFunction newProxy = vHYPEWithExtraFunction(payable(address(token)));
        vm.expectRevert();
        newProxy.extraFunction();
    }

    function test_ProtocolRegistryUpgradeToAndCall_NewOwner() public {
        address originalOwner = owner;
        address newOwner = makeAddr("newOwner");

        // Transfer ownership using 2-step process
        vm.prank(originalOwner);
        protocolRegistry.transferOwnership(newOwner);

        vm.prank(newOwner);
        protocolRegistry.acceptOwnership();

        // Verify ownership has been transferred
        assertEq(protocolRegistry.owner(), newOwner);

        // New owner upgrades the contract
        vHYPEWithExtraFunction newImplementation = new vHYPEWithExtraFunction();
        vm.prank(newOwner);
        token.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(token.protocolRegistry()), address(protocolRegistry));

        // Check that the extra function is available
        vHYPEWithExtraFunction newProxy = vHYPEWithExtraFunction(payable(address(token)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        vHYPEWithExtraFunction anotherImplementation = new vHYPEWithExtraFunction();
        vm.prank(originalOwner);
        vm.expectRevert("Caller is not the owner");
        token.upgradeToAndCall(address(anotherImplementation), "");
    }
}

contract vHYPEWithExtraFunction is vHYPE {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
