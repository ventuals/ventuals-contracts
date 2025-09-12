// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {GenesisVaultManager} from "../src/GenesisVaultManager.sol";
import {console} from "forge-std/console.sol";

contract SuccessiveDeposits {
    GenesisVaultManager public genesisVaultManager;

    event GenesisVaultManagerTotalBalance(uint256 totalBalance, string message);

    constructor(address payable _genesisVaultManager) {
        genesisVaultManager = GenesisVaultManager(_genesisVaultManager);
    }

    function successiveDeposits() public payable {
        uint256 amount = msg.value;
        emit GenesisVaultManagerTotalBalance(genesisVaultManager.totalBalance(), "Before first deposit");
        genesisVaultManager.deposit{value: amount / 2}();
        emit GenesisVaultManagerTotalBalance(genesisVaultManager.totalBalance(), "After first deposit");
        genesisVaultManager.deposit{value: amount / 2}();
        emit GenesisVaultManagerTotalBalance(genesisVaultManager.totalBalance(), "After second deposit");
    }

    receive() external payable {}
    fallback() external payable {}
}

contract DeploySuccessiveDeposits is Script {
    function run() public {
        address genesisVaultManagerAddress = vm.envAddress("GENESIS_VAULT_MANAGER");
        require(genesisVaultManagerAddress != address(0), "GenesisVaultManager address is not set");

        vm.startBroadcast();

        SuccessiveDeposits successiveDeposits = new SuccessiveDeposits(payable(genesisVaultManagerAddress));
        console.log("SuccessiveDeposits deployed to:", address(successiveDeposits));

        vm.stopBroadcast();
    }
}
