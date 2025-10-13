// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library Converters {
    /// @dev Convert an amount from 8 decimals to 18 decimals. Used for converting HYPE values from HyperCore to 18 decimals.
    function to18Decimals(uint64 amount) internal pure returns (uint256) {
        return uint256(amount) * 1e10;
    }

    /// @dev Convert an amount from 18 decimals to 8 decimals. Used for converting HYPE values to 8 decimals before sending to HyperCore.
    function to8Decimals(uint256 amount) internal pure returns (uint64) {
        return SafeCast.toUint64(amount / 1e10);
    }

    /// @dev Strips the last 10 decimal places from an amount. Used for converting HYPE values to 8 decimals before sending to HyperCore.
    function stripUnsafePrecision(uint256 amount) internal pure returns (uint256) {
        return amount / 1e10 * 1e10;
    }
}
