// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Converters} from "../../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../../src/libraries/L1ReadLibrary.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockHypeSystemContract {
    using Converters for *;

    address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    address public immutable mockHyperCoreStateAddress;

    constructor(address _mockHyperCoreStateAddress) {
        mockHyperCoreStateAddress = _mockHyperCoreStateAddress;
    }

    receive() external payable {
        MockHyperCoreState(mockHyperCoreStateAddress).recordSystemTransfer(msg.sender, HYPE_SYSTEM_ADDRESS, msg.value);
    }
}
