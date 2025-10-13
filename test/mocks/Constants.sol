// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

library Constants {
    address public constant MOCK_HYPERCORE_STATE_ADDRESS = address(uint160(uint256(keccak256("MockHyperCoreState"))));

    address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
    uint64 public constant HYPE_TOKEN_ID = 150;

    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address public constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
}
