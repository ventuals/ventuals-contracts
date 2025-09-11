// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployStakingVault is Script {
    address public constant ROLE_REGISTRY = address(0x812C84b0AFED921D3F686b8A39c0e0282D918b8a);

    function run() public {
        vm.startBroadcast();

        StakingVault implementation = new StakingVault();
        bytes memory initData = abi.encodeWithSelector(StakingVault.initialize.selector, ROLE_REGISTRY);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("StakingVault (proxy) deployed to:", address(proxy));
        console.log("StakingVault (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
