// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Constants} from "./Constants.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockPrecompileCoreUserExists {
    fallback(bytes calldata data) external returns (bytes memory) {
        (address user) = abi.decode(data, (address));
        return abi.encode(MockHyperCoreState(Constants.MOCK_HYPERCORE_STATE_ADDRESS).coreUserExists(user));
    }
}
