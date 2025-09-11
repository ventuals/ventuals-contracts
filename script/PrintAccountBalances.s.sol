// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {L1ReadAdapter} from "./utils/L1ReadAdapter.sol";

contract PrintAccountBalances is Script {
    function run() public {
        address account = vm.envAddress("ACCOUNT");
        string memory name = vm.envOr("NAME", vm.toString(account));
        L1ReadAdapter.initialize();
        printAccountBalances(account, name);
    }

    function printAccountBalances(address user, string memory name) public view {
        console.log("====", name, "====");
        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(user);
        console.log("Core user exists:", coreUserExists.exists);
        uint256 balance = address(user).balance;
        console.log("EVM balance:", balance);
        L1ReadLibrary.SpotBalance memory spotBalance = L1ReadLibrary.spotBalance(user, 1105);
        console.log("Spot balance:", spotBalance.total);
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = L1ReadLibrary.delegatorSummary(user);
        console.log("Delegated:", delegatorSummary.delegated);
        console.log("Undelegated:", delegatorSummary.undelegated);
        console.log("Total pending withdrawal:", delegatorSummary.totalPendingWithdrawal);
        console.log("Number of pending withdrawals:", delegatorSummary.nPendingWithdrawals);
    }
}
