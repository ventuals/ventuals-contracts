// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockHyperCoreState} from "./MockHyperCoreState.sol";
import {ICoreWriter} from "../src/interfaces/ICoreWriter.sol";
import {console} from "forge-std/console.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";

contract MockCoreWriter is ICoreWriter {
    address internal constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

    function sendRawAction(bytes calldata data) external {
        MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).sendRawAction(msg.sender, data);
    }
}
