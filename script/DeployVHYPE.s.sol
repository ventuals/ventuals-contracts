// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {VHYPE} from "../src/VHYPE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployVHYPE is Script {
    function run() public {
        address roleRegistry = vm.envAddress("ROLE_REGISTRY");
        require(roleRegistry != address(0), "RoleRegistry address is not set");

        vm.startBroadcast();

        VHYPE implementation = new VHYPE();
        bytes memory initData = abi.encodeWithSelector(VHYPE.initialize.selector, roleRegistry);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("VHYPE (proxy) deployed to:", address(proxy));
        console.log("VHYPE (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
