// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Constants} from "./Constants.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockHypeSystemContract {
    receive() external payable {
        MockHyperCoreState(Constants.MOCK_HYPERCORE_STATE_ADDRESS)
            .recordSystemTransfer(msg.sender, Constants.HYPE_SYSTEM_ADDRESS, msg.value);
    }
}
