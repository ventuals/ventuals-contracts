// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {L1ReadAdapter} from "./utils/L1ReadAdapter.sol";

/// @dev Usage: forge script PrintAccountBalances --rpc-url testnet --skip-simulation --disable-code-size-limit
contract PrintAccountBalances is Script {
    function run() public {
        address account = vm.parseAddress(vm.prompt("Enter account address"));
        require(account != address(0), "Invalid account address");
        string memory name = vm.prompt("Enter name (optional)");
        L1ReadAdapter.initialize();
        printAccountBalances(account, name);
    }

    function printAccountBalances(address user, string memory name) public view {
        console.log("\n");
        console.log("==================================================");
        if (bytes(name).length > 0) console.log(name);
        console.log("Address:", user);
        console.log("==================================================");

        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(user);
        console.log("Core user exists:             ", coreUserExists.exists ? "Yes" : "No");

        console.log("\n");

        uint256 balance = address(user).balance;
        console.log("EVM balance:                  ", balance);

        L1ReadLibrary.SpotBalance memory spotBalance = L1ReadLibrary.spotBalance(user, 1105);
        console.log("Spot balance:                 ", spotBalance.total);

        L1ReadLibrary.DelegatorSummary memory delegatorSummary = L1ReadLibrary.delegatorSummary(user);
        uint64 stakingBalance =
            delegatorSummary.delegated + delegatorSummary.undelegated + delegatorSummary.totalPendingWithdrawal;
        console.log("Staking balance:              ", stakingBalance);

        console.log("\n");
        console.log("Delegation Information:");
        console.log("--------------------------------------------------");
        console.log("Delegated:                    ", delegatorSummary.delegated);
        console.log("Undelegated:                  ", delegatorSummary.undelegated);
        console.log("Total pending withdrawal:     ", delegatorSummary.totalPendingWithdrawal);
        console.log("Number of pending withdrawals:", delegatorSummary.nPendingWithdrawals);
        console.log("==================================================\n");
    }
}
