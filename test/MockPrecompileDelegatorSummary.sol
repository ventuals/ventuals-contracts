// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockPrecompileDelegatorSummary {
    address internal constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

    fallback(bytes calldata data) external returns (bytes memory) {
        (address user) = abi.decode(data, (address));
        return abi.encode(MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).delegatorSummary(user));
    }
}
