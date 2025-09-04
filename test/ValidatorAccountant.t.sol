// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IValidatorAccountant} from "../src/interfaces/IValidatorAccountant.sol";
import {ValidatorAccountant} from "../src/ValidatorAccountant.sol";

contract ValidatorAccountantTest is Test {
    ValidatorAccountant public validatorAccountant;

    address public admin = address(0x1);
    address public manager = address(0x2);
    address public validator1 = address(0x3);
    address public validator2 = address(0x4);
    address public validator3 = address(0x5);

    function setUp() public {
        address[] memory initialEnabledValidators = new address[](3);
        initialEnabledValidators[0] = validator1;
        initialEnabledValidators[1] = validator2;
        initialEnabledValidators[2] = validator3;
        uint64[] memory initialTargetDelegationAmounts = new uint64[](3);
        initialTargetDelegationAmounts[0] = 100;
        initialTargetDelegationAmounts[1] = 100;
        initialTargetDelegationAmounts[2] = 100;

        ValidatorAccountant implementation = new ValidatorAccountant();
        bytes memory initData = abi.encodeWithSelector(
            ValidatorAccountant.initialize.selector,
            admin,
            manager,
            initialEnabledValidators,
            initialTargetDelegationAmounts
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        validatorAccountant = ValidatorAccountant(address(proxy));
    }

    function test_DelegationInstructions_Delegate() public view {
        IValidatorAccountant.DelegationInstruction[] memory instructions =
            validatorAccountant.delegationInstructions(50, false);
        assertEq(instructions.length, 1);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 50);
        assertEq(instructions[0].isUndelegate, false);

        instructions = validatorAccountant.delegationInstructions(100, false);
        assertEq(instructions.length, 1);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 100);
        assertEq(instructions[0].isUndelegate, false);

        instructions = validatorAccountant.delegationInstructions(150, false);
        assertEq(instructions.length, 2);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 100);
        assertEq(instructions[0].isUndelegate, false);
        assertEq(instructions[1].validator, validator2);
        assertEq(instructions[1].weiAmount, 50);
        assertEq(instructions[1].isUndelegate, false);

        instructions = validatorAccountant.delegationInstructions(500, false);
        assertEq(instructions.length, 3);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 300);
        assertEq(instructions[0].isUndelegate, false);
        assertEq(instructions[1].validator, validator2);
        assertEq(instructions[1].weiAmount, 100);
        assertEq(instructions[1].isUndelegate, false);
        assertEq(instructions[2].validator, validator3);
        assertEq(instructions[2].weiAmount, 100);
        assertEq(instructions[2].isUndelegate, false);
    }

    function test_DelegationInstructions_Undelegate() public {
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator1, 100, false);
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator2, 100, false);
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator3, 50, false);

        IValidatorAccountant.DelegationInstruction[] memory instructions =
            validatorAccountant.delegationInstructions(30, true);
        assertEq(instructions.length, 1);
        assertEq(instructions[0].validator, validator3);
        assertEq(instructions[0].weiAmount, 30);
        assertEq(instructions[0].isUndelegate, true);

        instructions = validatorAccountant.delegationInstructions(100, true);
        assertEq(instructions.length, 2);
        assertEq(instructions[0].validator, validator2);
        assertEq(instructions[0].weiAmount, 50);
        assertEq(instructions[0].isUndelegate, true);
        assertEq(instructions[1].validator, validator3);
        assertEq(instructions[1].weiAmount, 50);
        assertEq(instructions[1].isUndelegate, true);

        instructions = validatorAccountant.delegationInstructions(220, true);
        assertEq(instructions.length, 3);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 70);
        assertEq(instructions[0].isUndelegate, true);
        assertEq(instructions[1].validator, validator2);
        assertEq(instructions[1].weiAmount, 100);
        assertEq(instructions[1].isUndelegate, true);
        assertEq(instructions[2].validator, validator3);
        assertEq(instructions[2].weiAmount, 50);
        assertEq(instructions[2].isUndelegate, true);

        instructions = validatorAccountant.delegationInstructions(250, true);
        assertEq(instructions.length, 3);
        assertEq(instructions[0].validator, validator1);
        assertEq(instructions[0].weiAmount, 100);
        assertEq(instructions[0].isUndelegate, true);
        assertEq(instructions[1].validator, validator2);
        assertEq(instructions[1].weiAmount, 100);
        assertEq(instructions[1].isUndelegate, true);
        assertEq(instructions[2].validator, validator3);
        assertEq(instructions[2].weiAmount, 50);
        assertEq(instructions[2].isUndelegate, true);
    }

    function test_RecordDelegation() public {
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator1, 100, false);
        assertEq(validatorAccountant.delegatedAmounts(validator1), 100);
        assertEq(validatorAccountant.totalDelegatedAmount(), 100);

        vm.prank(manager);
        validatorAccountant.recordDelegation(validator2, 50, false);
        assertEq(validatorAccountant.delegatedAmounts(validator2), 50);
        assertEq(validatorAccountant.totalDelegatedAmount(), 150);

        vm.prank(manager);
        validatorAccountant.recordDelegation(validator1, 30, true);
        assertEq(validatorAccountant.delegatedAmounts(validator1), 70);
        assertEq(validatorAccountant.totalDelegatedAmount(), 120);
    }

    function test_RecordDelegation_OnlyManager() public {
        vm.expectRevert("Caller is not a manager");
        validatorAccountant.recordDelegation(validator1, 100, false);

        vm.prank(admin);
        vm.expectRevert("Caller is not a manager");
        validatorAccountant.recordDelegation(validator1, 100, false);
    }

    function test_RecordDelegation_UndelegateExceedsBalance() public {
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator1, 50, false);

        vm.prank(manager);
        vm.expectRevert("Amount to undelegate from validator exceeds delegated amount to validator");
        validatorAccountant.recordDelegation(validator1, 100, true);
    }

    function test_AddValidator() public {
        address newValidator = address(0x6);
        vm.prank(admin);
        validatorAccountant.addValidator(newValidator, 200);

        assertEq(validatorAccountant.enabledValidators(3), newValidator);
        assertEq(validatorAccountant.targetDelegationAmounts(newValidator), 200);
    }

    function test_AddValidator_OnlyAdmin() public {
        address newValidator = address(0x6);

        vm.expectRevert("Caller is not an admin");
        validatorAccountant.addValidator(newValidator, 200);

        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.addValidator(newValidator, 200);
    }

    function test_RemoveValidator() public {
        assertEq(validatorAccountant.enabledValidators(1), validator2);
        assertEq(validatorAccountant.targetDelegationAmounts(validator2), 100);

        vm.prank(admin);
        validatorAccountant.removeValidator(validator2);

        assertEq(validatorAccountant.enabledValidators(1), validator3);
        assertEq(validatorAccountant.targetDelegationAmounts(validator2), 0);
    }

    function test_RemoveValidator_OnlyAdmin() public {
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.removeValidator(validator2);

        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.removeValidator(validator2);
    }

    function test_Pause() public {
        assertFalse(validatorAccountant.paused());

        vm.prank(admin);
        validatorAccountant.pause();
        assertTrue(validatorAccountant.paused());
    }

    function test_Pause_OnlyAdmin() public {
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.pause();

        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.pause();
    }

    function test_Unpause() public {
        vm.prank(admin);
        validatorAccountant.pause();
        assertTrue(validatorAccountant.paused());

        vm.prank(admin);
        validatorAccountant.unpause();
        assertFalse(validatorAccountant.paused());
    }

    function test_Unpause_OnlyAdmin() public {
        vm.prank(admin);
        validatorAccountant.pause();

        vm.expectRevert("Caller is not an admin");
        validatorAccountant.unpause();

        vm.prank(manager);
        vm.expectRevert("Caller is not an admin");
        validatorAccountant.unpause();
    }

    function test_DelegationInstructions_ZeroAmount() public {
        vm.expectRevert("Wei amount must be greater than 0");
        validatorAccountant.delegationInstructions(0, false);
    }

    function test_DelegationInstructions_UndelegateExceedsTotalDelegated() public {
        vm.prank(manager);
        validatorAccountant.recordDelegation(validator1, 50, false);

        vm.expectRevert("Amount to undelegate exceeds total delegated amount");
        validatorAccountant.delegationInstructions(100, true);
    }

    function test_Initialize_MismatchedArrayLengths() public {
        address[] memory validators = new address[](2);
        validators[0] = validator1;
        validators[1] = validator2;

        uint64[] memory amounts = new uint64[](1);
        amounts[0] = 100;

        ValidatorAccountant implementation = new ValidatorAccountant();
        bytes memory initData =
            abi.encodeWithSelector(ValidatorAccountant.initialize.selector, admin, manager, validators, amounts);

        vm.expectRevert("Initial enabled validators and target delegation amounts must have the same length");
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_GetValidatorData() public view {
        assertEq(validatorAccountant.enabledValidators(0), validator1);
        assertEq(validatorAccountant.enabledValidators(1), validator2);
        assertEq(validatorAccountant.enabledValidators(2), validator3);
        assertEq(validatorAccountant.targetDelegationAmounts(validator1), 100);
        assertEq(validatorAccountant.targetDelegationAmounts(validator2), 100);
        assertEq(validatorAccountant.targetDelegationAmounts(validator3), 100);
        assertEq(validatorAccountant.delegatedAmounts(validator1), 0);
        assertEq(validatorAccountant.totalDelegatedAmount(), 0);
    }
}
