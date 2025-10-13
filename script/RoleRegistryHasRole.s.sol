// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {console} from "forge-std/console.sol";

contract RoleRegistryHasRole is Script {
    function run() public view {
        address roleRegistryAddress = vm.envAddress("ROLE_REGISTRY");
        string memory roleString = vm.envString("ROLE");
        address account = vm.envAddress("ACCOUNT");

        require(roleRegistryAddress != address(0), "RoleRegistry address is not set");
        require(account != address(0), "Account is not set");

        RoleRegistry roleRegistry = RoleRegistry(roleRegistryAddress);

        bytes32 role;
        if (_strEqual(roleString, "manager")) {
            role = roleRegistry.MANAGER_ROLE();
        } else if (_strEqual(roleString, "operator")) {
            role = roleRegistry.OPERATOR_ROLE();
        } else {
            revert("Unrecognized role");
        }

        console.log("RoleRegistry address:", roleRegistryAddress);
        bool hasRole = roleRegistry.hasRole(role, account);
        if (hasRole) {
            console.log("Account has role:", roleString);
        } else {
            console.log("Account does not have role:", roleString);
        }
    }

    function _strEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
