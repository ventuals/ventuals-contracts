// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IValidatorAccountant} from "./interfaces/IValidatorAccountant.sol";

contract ValidatorAccountant is IValidatorAccountant, Initializable, PausableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    address[] public enabledValidators;
    mapping(address => uint64) public targetDelegationAmounts;
    mapping(address => uint64) public delegatedAmounts;
    uint64 public totalDelegatedAmount;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address manager,
        address[] calldata initialEnabledValidators,
        uint64[] calldata initialTargetDelegationAmounts
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MANAGER_ROLE, manager);

        require(
            initialEnabledValidators.length == initialTargetDelegationAmounts.length,
            "Initial enabled validators and target delegation amounts must have the same length"
        );

        for (uint256 i = 0; i < initialEnabledValidators.length; i++) {
            enabledValidators.push(initialEnabledValidators[i]);
            targetDelegationAmounts[initialEnabledValidators[i]] = initialTargetDelegationAmounts[i];
        }
    }

    function delegationInstructions(uint64 weiAmount, bool isUndelegate)
        public
        view
        returns (DelegationInstruction[] memory)
    {
        require(weiAmount > 0, "Wei amount must be greater than 0");
        require(enabledValidators.length > 0, "No enabled validators");

        if (isUndelegate) {
            require(totalDelegatedAmount >= weiAmount, "Amount to undelegate exceeds total delegated amount");
            return _undelegate(weiAmount);
        } else {
            return _delegate(weiAmount);
        }
    }

    function _delegate(uint64 weiAmount) private view returns (DelegationInstruction[] memory) {
        uint64 amountLeftToDelegate = weiAmount;
        DelegationInstruction[] memory instructions = new DelegationInstruction[](enabledValidators.length);

        for (uint256 i = 0; i < enabledValidators.length; i++) {
            // We haven't reached the target delegation amount
            if (delegatedAmounts[enabledValidators[i]] < targetDelegationAmounts[enabledValidators[i]]) {
                uint64 amountLeftToTarget =
                    targetDelegationAmounts[enabledValidators[i]] - delegatedAmounts[enabledValidators[i]];

                if (amountLeftToDelegate > amountLeftToTarget) {
                    instructions[i] = DelegationInstruction({
                        validator: enabledValidators[i],
                        weiAmount: amountLeftToTarget,
                        isUndelegate: false
                    });
                    amountLeftToDelegate -= amountLeftToTarget;
                } else {
                    instructions[i] = DelegationInstruction({
                        validator: enabledValidators[i],
                        weiAmount: amountLeftToDelegate,
                        isUndelegate: false
                    });
                    amountLeftToDelegate = 0;
                }
            }
        }

        // If we still have some wei left to delegate, just delegate it to the first validator
        if (amountLeftToDelegate > 0) {
            instructions[0] = DelegationInstruction({
                validator: enabledValidators[0],
                weiAmount: amountLeftToDelegate,
                isUndelegate: false
            });
        }

        return instructions;
    }

    function _undelegate(uint64 weiAmount) private view returns (DelegationInstruction[] memory) {
        uint64 amountLeftToUndelegate = weiAmount;
        DelegationInstruction[] memory instructions = new DelegationInstruction[](enabledValidators.length);

        // Iterate over enabled validators in reverse order
        for (uint256 i = enabledValidators.length - 1; i >= 0; i--) {
            uint64 validatorDelegatedAmount = delegatedAmounts[enabledValidators[i]];
            // If the validator has any delegated amount
            if (validatorDelegatedAmount > 0) {
                if (amountLeftToUndelegate > validatorDelegatedAmount) {
                    instructions[i] = DelegationInstruction({
                        validator: enabledValidators[i],
                        weiAmount: validatorDelegatedAmount,
                        isUndelegate: true
                    });
                    amountLeftToUndelegate -= validatorDelegatedAmount;
                } else {
                    instructions[i] = DelegationInstruction({
                        validator: enabledValidators[i],
                        weiAmount: amountLeftToUndelegate,
                        isUndelegate: true
                    });
                    amountLeftToUndelegate = 0;
                }
            }
        }

        return instructions;
    }

    function recordDelegation(address validator, uint64 weiAmount, bool isUndelegate) public onlyManager {
        if (isUndelegate) {
            require(
                delegatedAmounts[validator] >= weiAmount,
                "Amount to undelegate from validator exceeds delegated amount to validator"
            );
            delegatedAmounts[validator] -= weiAmount;
            totalDelegatedAmount -= weiAmount;
        } else {
            delegatedAmounts[validator] += weiAmount;
            totalDelegatedAmount += weiAmount;
        }
    }

    function addValidator(address validator, uint64 delegationAmount) public onlyAdmin {
        enabledValidators.push(validator);
        targetDelegationAmounts[validator] = delegationAmount;
    }

    function removeValidator(address validator) public onlyAdmin {
        address[] memory newEnabledValidators = new address[](enabledValidators.length - 1);

        uint256 j = 0;
        for (uint256 i = 0; i < enabledValidators.length; i++) {
            if (enabledValidators[i] != validator) {
                newEnabledValidators[j] = enabledValidators[i];
                j++;
            }
        }

        enabledValidators = newEnabledValidators;
        delete targetDelegationAmounts[validator];
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a manager");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }
}
