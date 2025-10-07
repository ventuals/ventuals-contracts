// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockHyperCoreState} from "./MockHyperCoreState.sol";

contract MockPrecompileSpotBalance {
    address internal constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

    fallback(bytes calldata data) external returns (bytes memory) {
        (address user, uint64 token) = abi.decode(data, (address, uint64));
        return abi.encode(MockHyperCoreState(MOCK_HYPERCORE_STATE_ADDRESS).spotBalance(user, token));
    }
}
