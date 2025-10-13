// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Constants} from "./Constants.sol";
import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockPrecompileSpotBalance {
    fallback(bytes calldata data) external returns (bytes memory) {
        (address user, uint64 token) = abi.decode(data, (address, uint64));
        return abi.encode(MockHyperCoreState(Constants.MOCK_HYPERCORE_STATE_ADDRESS).spotBalance(user, token));
    }
}
