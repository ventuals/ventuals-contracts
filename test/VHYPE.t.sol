// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract VHYPETest is Test {
    RoleRegistry roleRegistry;
    /// forge-lint: disable-next-line(mixed-case-variable)
    VHYPE public vHYPE;

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");

    function setUp() public {
        RoleRegistry roleRegistryImplementation = new RoleRegistry();
        bytes memory roleRegistryInitData = abi.encodeWithSelector(RoleRegistry.initialize.selector, owner);
        ERC1967Proxy roleRegistryProxy = new ERC1967Proxy(address(roleRegistryImplementation), roleRegistryInitData);
        roleRegistry = RoleRegistry(address(roleRegistryProxy));

        VHYPE implementation = new VHYPE();
        bytes memory initData = abi.encodeWithSelector(VHYPE.initialize.selector, address(roleRegistryProxy));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        vHYPE = VHYPE(address(proxy));

        vm.startPrank(owner);
        roleRegistry.grantRole(roleRegistry.MANAGER_ROLE(), manager);
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

    function test_Mint_NotManager(address notManager, uint256 amount) public {
        vm.assume(notManager != manager);
        vm.assume(notManager != address(0));
        vm.assume(amount > 0);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        vHYPE.mint(notManager, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Tests: Burn                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function test_Burn_OnlyManager(uint256 amount, uint256 burnAmount) public {
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);
        vm.assume(burnAmount > 0);

        vm.prank(manager);
        vHYPE.mint(manager, amount);

        vm.prank(manager);
        vHYPE.burn(burnAmount);

        assertEq(vHYPE.balanceOf(manager), amount - burnAmount);
        assertEq(vHYPE.totalSupply(), amount - burnAmount);
    }

    function test_Burn_NotManager(address notManager, uint256 amount, uint256 burnAmount) public {
        vm.assume(notManager != manager);
        vm.assume(notManager != address(0));
        vm.assume(amount > 0);
        vm.assume(amount > burnAmount);
        vm.assume(burnAmount > 0);

        vm.prank(manager);
        vHYPE.mint(notManager, amount);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        vHYPE.burn(burnAmount);
    }

    function test_Burn_CannotBurnMoreThanBalance(uint256 amount, uint256 burnAmount) public {
        vm.assume(amount > 0);
        vm.assume(burnAmount > amount);

        vm.prank(manager);
        vHYPE.mint(manager, amount);

        vm.prank(manager);
        vm.expectRevert();
        vHYPE.burn(burnAmount);
    }

    function test_Burn_WhenPaused() public {
        uint256 amount = 1000e18;
        uint256 burnAmount = 500e18;

        vm.prank(manager);
        vHYPE.mint(manager, amount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(vHYPE));

        vm.prank(manager);
        vm.expectRevert();
        vHYPE.burn(burnAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Tests: Burn From                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_BurnFrom_OnlyManager(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(user != manager);
        vm.assume(amount > 0);
        vm.assume(amount >= burnAmount);
        vm.assume(burnAmount > 0);
        vm.assume(burnAmount < type(uint256).max); // Exclude max uint256 to avoid infinite approval behavior

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vHYPE.approve(manager, burnAmount);

        vm.prank(manager);
        vHYPE.burnFrom(user, burnAmount);

        assertEq(vHYPE.balanceOf(user), amount - burnAmount);
        assertEq(vHYPE.totalSupply(), amount - burnAmount);
        assertEq(vHYPE.allowance(user, manager), 0);
    }

    function test_BurnFrom_NotManager(address notManager, address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(notManager != manager);
        vm.assume(notManager != address(0));
        vm.assume(user != address(0));
        vm.assume(user != notManager);
        vm.assume(user != manager);
        vm.assume(amount > 0);
        vm.assume(burnAmount > 0);
        vm.assume(amount >= burnAmount);

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vHYPE.approve(notManager, burnAmount);

        vm.startPrank(notManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, notManager, roleRegistry.MANAGER_ROLE()
            )
        );
        vHYPE.burnFrom(user, burnAmount);
    }

    function test_BurnFrom_InsufficientAllowance(address user, uint256 amount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        vm.assume(user != manager);
        vm.assume(amount > 0);
        vm.assume(burnAmount > 1);
        vm.assume(amount >= burnAmount);

        uint256 approval = burnAmount - 1;

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vHYPE.approve(manager, approval);

        vm.prank(manager);
        vm.expectRevert();
        vHYPE.burnFrom(user, burnAmount);
    }

    function test_BurnFrom_WhenPaused() public {
        address user = makeAddr("user");
        uint256 amount = 1000e18;
        uint256 burnAmount = 500e18;

        vm.prank(manager);
        vHYPE.mint(user, amount);

        vm.prank(user);
        vHYPE.approve(manager, burnAmount);

        // Pause the contract
        vm.prank(owner);
        roleRegistry.pause(address(vHYPE));

        vm.prank(manager);
        vm.expectRevert();
        vHYPE.burnFrom(user, burnAmount);
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
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
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
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
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
        assertEq(address(vHYPE.roleRegistry()), address(roleRegistry));

        // Check that the extra function is available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
        assertTrue(newProxy.extraFunction());
    }

    function test_UpgradeToAndCall_NotOwner(address notOwner) public {
        vm.assume(notOwner != owner);

        VHYPEWithExtraFunction newImplementation = new VHYPEWithExtraFunction();

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, notOwner));
        vHYPE.upgradeToAndCall(address(newImplementation), "");

        // Check that the extra function is not available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
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
        VHYPEWithExtraFunction newImplementation = new VHYPEWithExtraFunction();
        vm.prank(newOwner);
        vHYPE.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade preserved state
        assertEq(address(vHYPE.roleRegistry()), address(roleRegistry));

        // Check that the extra function is available
        VHYPEWithExtraFunction newProxy = VHYPEWithExtraFunction(payable(address(vHYPE)));
        assertTrue(newProxy.extraFunction());

        // Verify that the old owner can no longer upgrade
        VHYPEWithExtraFunction anotherImplementation = new VHYPEWithExtraFunction();
        vm.prank(originalOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, originalOwner));
        vHYPE.upgradeToAndCall(address(anotherImplementation), "");
    }
}

contract VHYPEWithExtraFunction is VHYPE {
    function extraFunction() public pure returns (bool) {
        return true;
    }
}
