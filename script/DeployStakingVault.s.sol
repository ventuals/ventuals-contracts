// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract DeployStakingVault is Script {
    address public constant ADMIN = address(0x71D9eD6c257fB7872E1AB289ABfC374B5d1C61bC);
    address public constant MANAGER = address(0x71D9eD6c257fB7872E1AB289ABfC374B5d1C61bC);
    address public constant OPERATOR = address(0x71D9eD6c257fB7872E1AB289ABfC374B5d1C61bC);

    function run() public {
        vm.startBroadcast();

        StakingVault implementation = new StakingVault();
        bytes memory initData = abi.encodeWithSelector(StakingVault.initialize.selector, ADMIN, MANAGER, OPERATOR);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("StakingVault (proxy) deployed to:", address(proxy));
        console.log("StakingVault (implementation) deployed to:", address(implementation));

        vm.stopBroadcast();
    }
}
