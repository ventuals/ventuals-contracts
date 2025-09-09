// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProtocolRegistry} from "../src/ProtocolRegistry.sol";

contract VHYPETest is Test {
    ProtocolRegistry protocolRegistry;
    VHYPE public vHYPE;

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");

    function setUp() public {
        ProtocolRegistry protocolRegistryImplementation = new ProtocolRegistry();
        bytes memory protocolRegistryInitData = abi.encodeWithSelector(ProtocolRegistry.initialize.selector, owner);
        ERC1967Proxy protocolRegistryProxy =
            new ERC1967Proxy(address(protocolRegistryImplementation), protocolRegistryInitData);
        protocolRegistry = ProtocolRegistry(address(protocolRegistryProxy));

        VHYPE implementation = new VHYPE();
        bytes memory initData = abi.encodeWithSelector(VHYPE.initialize.selector, address(protocolRegistryProxy));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vHYPE = VHYPE(address(proxy));

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
        vHYPE.mint(user, amount);
        assertEq(vHYPE.balanceOf(user), amount);
        assertEq(vHYPE.totalSupply(), amount);
    }

    function test_Mint_NotManager(address user, uint256 amount) public {
        vm.assume(user != address(0));
        vm.assume(user != manager);
        vm.assume(amount > 0);

        vm.prank(user);
        vm.expectRevert();
        vHYPE.mint(user, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Burn                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_CanBurnOwnTokens(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vHYPE.burn(burnAmount);

        assertEq(vHYPE.balanceOf(user), amount - burnAmount);
        assertEq(vHYPE.totalSupply(), amount - burnAmount);
    }

    function test_CanBurnWithApproval(address user1, address user2, uint256 amount, uint256 burnAmount) public {
        vm.assume(user1 != address(0));
        vm.assume(user2 != address(0));
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);

        vm.prank(manager);
        vHYPE.mint(user1, amount);

        vm.prank(user1);
        vHYPE.approve(user2, burnAmount);

        vm.prank(user2);
        vHYPE.burnFrom(user1, burnAmount);

        assertEq(vHYPE.balanceOf(user1), amount - burnAmount);
        assertEq(vHYPE.totalSupply(), amount - burnAmount);
        assertEq(vHYPE.allowance(user1, user2), 0);
    }

    function test_CannotBurnMoreThanBalance(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(amount > 0);
        vm.assume(burnAmount > amount);

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vm.expectRevert();
        vHYPE.burn(burnAmount);
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
        vHYPE.mint(user1, amount);

        vm.prank(user1);
        vHYPE.transfer(user2, transferAmount);

        assertEq(vHYPE.balanceOf(user1), amount - transferAmount);
        assertEq(vHYPE.balanceOf(user2), transferAmount);
    }

    function test_ApproveAndTransferFrom(uint256 amount, uint256 transferAmount) public {
        vm.assume(amount > 0);
        vm.assume(amount > transferAmount);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.prank(manager);
        vHYPE.mint(user1, amount);

        vm.prank(user1);
        vHYPE.approve(user2, transferAmount);

        vm.prank(user2);
        vHYPE.transferFrom(user1, user2, transferAmount);

        assertEq(vHYPE.balanceOf(user1), amount - transferAmount);
        assertEq(vHYPE.balanceOf(user2), transferAmount);
        assertEq(vHYPE.allowance(user1, user2), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 Tests: Upgradeability                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_UpgradeToAndCall_OnlyOwner() public {
        VHYPEWithExtraFunction newImplementation = new VHYPEWithExtraFunction();

        vm.prank(owner);
        vHYPE.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(vHYPE.protocolRegistry()), address(protocolRegistry));

        // Check that the extra function is available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        VHYPEWithExtraFunction newImplementation = new VHYPEWithExtraFunction();

        vm.prank(notOwner);
        vm.expectRevert("Caller is not the owner");
        vHYPE.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
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
        VHYPEWithExtraFunction newImplementation = new VHYPEWithExtraFunction();
        vm.prank(newOwner);
        vHYPE.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(vHYPE.protocolRegistry()), address(protocolRegistry));

        // Check that the extra function is available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        VHYPEWithExtraFunction anotherImplementation = new VHYPEWithExtraFunction();
        vm.prank(originalOwner);
        vm.expectRevert("Caller is not the owner");
        vHYPE.upgradeToAndCall(address(anotherImplementation), "");
    }
}

contract VHYPEWithExtraFunction is VHYPE {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
