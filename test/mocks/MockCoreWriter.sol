// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockHyperCoreState} from "./MockHyperCoreState.sol";
import {ICoreWriter} from "../../src/interfaces/ICoreWriter.sol";
import {Constants} from "./Constants.sol";

contract MockCoreWriter is ICoreWriter {
    function sendRawAction(bytes calldata data) external {
        MockHyperCoreState(Constants.MOCK_HYPERCORE_STATE_ADDRESS).sendRawAction(msg.sender, data);
    }
}
