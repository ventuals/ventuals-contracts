// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {RoleRegistry} from "../src/RoleRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployRoleRegistry is Script {
    address public constant OWNER = address(0x71D9eD6c257fB7872E1AB289ABfC374B5d1C61bC);

    function run() public {
        vm.startBroadcast();

        RoleRegistry implementation = new RoleRegistry();
        bytes memory initData = abi.encodeWithSelector(RoleRegistry.initialize.selector, OWNER);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("RoleRegistry (proxy) deployed to:", address(proxy));
        console.log("RoleRegistry (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
