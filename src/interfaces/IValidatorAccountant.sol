// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IValidatorAccountant {
    struct DelegationInstruction {
        address validator;
        uint64 weiAmount;
        bool isUndelegate;
    }

    function delegationInstructions(uint64 weiAmount, bool isUndelegate)
        external
        view
        returns (DelegationInstruction[] memory);
}
