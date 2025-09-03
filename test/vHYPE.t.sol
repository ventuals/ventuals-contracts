// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {vHYPE} from "../src/vHYPE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract vHYPETest is Test {
    vHYPE public token;
    vHYPE public implementation;

    address public admin = address(0x1);
    address public pauser = address(0x2);
    address public minter = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public {
        implementation = new vHYPE();

        bytes memory initData = abi.encodeWithSelector(vHYPE.initialize.selector, admin, pauser, minter);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = vHYPE(address(proxy));
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        token.initialize(admin, pauser, minter);
    }

    // Access control
    function test_AdminCanGrantRoles() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, user1);
        assertTrue(token.hasRole(MINTER_ROLE, user1));
    }

    function test_AdminCanRevokeRoles() public {
        vm.prank(admin);
        token.revokeRole(MINTER_ROLE, minter);
        assertFalse(token.hasRole(MINTER_ROLE, minter));
    }

    function test_NonAdminCannotGrantRoles() public {
        vm.prank(user1);
        vm.expectRevert();
        token.grantRole(MINTER_ROLE, user2);
    }

    // Minting
    function test_MinterCanMint() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(minter);
        token.mint(user1, amount);
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_NonMinterCannotMint() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, amount);
    }

    function test_MintToZeroAddress() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(minter);
        vm.expectRevert();
        token.mint(address(0), amount);
    }

    // Pause/unpause
    function test_PauserCanPause() public {
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());
    }

    function test_PauserCanUnpause() public {
        vm.prank(pauser);
        token.pause();
        assertTrue(token.paused());

        vm.prank(pauser);
        token.unpause();
        assertFalse(token.paused());
    }

    function test_NonPauserCannotPause() public {
        vm.prank(user1);
        vm.expectRevert();
        token.pause();
    }

    function test_NonPauserCannotUnpause() public {
        vm.prank(pauser);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.unpause();
    }

    function test_TransferFailsWhenPaused() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(pauser);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 * 10 ** 18);
    }

    function test_TransferWorksWhenUnpaused() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(pauser);
        token.pause();

        vm.prank(pauser);
        token.unpause();

        vm.prank(user1);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user1), amount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
    }

    // Burn
    function test_UserCanBurnOwnTokens() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 burnAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), amount - burnAmount);
        assertEq(token.totalSupply(), amount - burnAmount);
    }

    function test_UserCanBurnFromWithApproval() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 burnAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, burnAmount);

        vm.prank(user2);
        token.burnFrom(user1, burnAmount);

        assertEq(token.balanceOf(user1), amount - burnAmount);
        assertEq(token.totalSupply(), amount - burnAmount);
        assertEq(token.allowance(user1, user2), 0);
    }

    function test_CannotBurnMoreThanBalance() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 burnAmount = 200 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(user1);
        vm.expectRevert();
        token.burn(burnAmount);
    }

    function test_BurnFailsWhenPaused() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 burnAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(pauser);
        token.pause();

        vm.prank(user1);
        vm.expectRevert();
        token.burn(burnAmount);
    }

    // Transfer
    function test_StandardTransfer() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(user1);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user1), amount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
    }

    function test_ApproveAndTransferFrom() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        vm.prank(minter);
        token.mint(user1, amount);

        vm.prank(user1);
        token.approve(user2, transferAmount);

        vm.prank(user2);
        token.transferFrom(user1, user2, transferAmount);

        assertEq(token.balanceOf(user1), amount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.allowance(user1, user2), 0);
    }

    // Fuzz
    function testFuzz_MintAmount(uint256 amount) public {
        vm.assume(amount <= type(uint256).max / 2);

        vm.prank(minter);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_TransferAmount(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount <= type(uint256).max / 2);
        vm.assume(transferAmount <= mintAmount);

        vm.prank(minter);
        token.mint(user1, mintAmount);

        vm.prank(user1);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user1), mintAmount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
    }
}
