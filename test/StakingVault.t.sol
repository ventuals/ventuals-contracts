// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";

contract StakingVaultTest is Test {
    StakingVault stakingVault;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public operator = address(0x3);

    function setUp() public {
        StakingVault implementation = new StakingVault();
        bytes memory initData = abi.encodeWithSelector(StakingVault.initialize.selector, admin, manager, operator);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        stakingVault = StakingVault(payable(proxy));
    }

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

    function test_TokenDelegate(address validator, uint64 weiAmount, bool isUndelegate) public {
        // Mock the CoreWriter call
        bytes memory encodedAction = abi.encode(validator, weiAmount, isUndelegate);
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
        stakingVault.tokenDelegate(validator, weiAmount, isUndelegate);
    }

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

    function test_TransferHype(uint256 amount) public {
        vm.deal(address(stakingVault), amount);

        vm.prank(manager);
        stakingVault.transferHype(amount);

        assertEq(address(stakingVault).balance, 0);
        assertEq(manager.balance, amount);
    }

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

    // Access Control Tests
    function test_StakingDeposit_OnlyManager() public {
        vm.deal(admin, 1e18);
        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        stakingVault.stakingDeposit(1e10);

        vm.deal(operator, 1e18);
        vm.prank(operator);
        vm.expectRevert("Caller is not a manager");
        stakingVault.stakingDeposit(1e10);
    }

    function test_StakingWithdraw_OnlyManager() public {
        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        stakingVault.stakingWithdraw(1e8);

        vm.prank(operator);
        vm.expectRevert("Caller is not a manager");
        stakingVault.stakingWithdraw(1e8);
    }

    function test_TokenDelegate_OnlyManager() public {
        address validator = address(0x123);
        uint64 weiAmount = 1e8;

        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        stakingVault.tokenDelegate(validator, weiAmount, false);

        vm.prank(operator);
        vm.expectRevert("Caller is not a manager");
        stakingVault.tokenDelegate(validator, weiAmount, false);
    }

    function test_SpotSend_OnlyManager() public {
        address destination = address(0x456);
        uint64 token = 0;
        uint64 weiAmount = 1e8;

        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        stakingVault.spotSend(destination, token, weiAmount);

        vm.prank(operator);
        vm.expectRevert("Caller is not a manager");
        stakingVault.spotSend(destination, token, weiAmount);
    }

    function test_TransferHype_OnlyManager() public {
        vm.deal(address(stakingVault), 1e18);
        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        stakingVault.transferHype(1e18);

        vm.prank(operator);
        vm.expectRevert("Caller is not a manager");
        stakingVault.transferHype(1e18);
    }

    function test_AddApiWallet_OnlyOperator() public {
        address apiWalletAddress = address(0x789);
        string memory name = "TestWallet";

        vm.prank(admin);
        vm.expectRevert("Caller is not an operator");
        stakingVault.addApiWallet(apiWalletAddress, name);

        vm.prank(manager);
        vm.expectRevert("Caller is not an operator");
        stakingVault.addApiWallet(apiWalletAddress, name);
    }

    function test_Pause_OnlyAdmin() public {
        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        stakingVault.pause();

        vm.prank(operator);
        vm.expectRevert("Caller is not an admin");
        stakingVault.pause();
    }

    function test_Unpause_OnlyAdmin() public {
        vm.prank(admin);
        stakingVault.pause();

        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        stakingVault.unpause();

        vm.prank(operator);
        vm.expectRevert("Caller is not an admin");
        stakingVault.unpause();
    }

    // Pause/Unpause Functionality Tests
    function test_Pause_Success() public {
        vm.prank(admin);
        stakingVault.pause();

        assertTrue(stakingVault.paused());
    }

    function test_Unpause_Success() public {
        vm.prank(admin);
        stakingVault.pause();

        vm.prank(admin);
        stakingVault.unpause();

        assertFalse(stakingVault.paused());
    }

    function test_FunctionsWhenPaused() public {
        vm.prank(admin);
        stakingVault.pause();

        vm.deal(manager, 1e18);
        vm.prank(manager);
        vm.expectRevert();
        stakingVault.stakingDeposit(1e10);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.stakingWithdraw(1e8);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.tokenDelegate(address(0x123), 1e8, false);

        vm.prank(manager);
        vm.expectRevert();
        stakingVault.spotSend(address(0x456), 0, 1e8);

        vm.prank(operator);
        vm.expectRevert();
        stakingVault.addApiWallet(address(0x789), "TestWallet");
    }

    // Initialization Tests
    function test_Initialization() public view {
        assertTrue(stakingVault.hasRole(stakingVault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(stakingVault.hasRole(stakingVault.MANAGER_ROLE(), manager));
        assertTrue(stakingVault.hasRole(stakingVault.OPERATOR_ROLE(), operator));

        assertFalse(stakingVault.paused());
    }

    function test_RoleConstants() public view {
        bytes32 expectedManagerRole = keccak256("MANAGER_ROLE");
        bytes32 expectedOperatorRole = keccak256("OPERATOR_ROLE");

        assertEq(stakingVault.MANAGER_ROLE(), expectedManagerRole);
        assertEq(stakingVault.OPERATOR_ROLE(), expectedOperatorRole);
    }

    // Edge Case Tests
    function test_StakingDeposit_ZeroAmount() public {
        bytes memory encodedAction = abi.encode(uint64(0));
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x04;
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
        stakingVault.stakingDeposit(0);
    }

    function test_StakingWithdraw_ZeroAmount() public {
        uint64 weiAmount = 0;
        bytes memory encodedAction = abi.encode(weiAmount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x05;
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
}
