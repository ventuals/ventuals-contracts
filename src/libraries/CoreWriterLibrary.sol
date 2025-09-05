// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

// @notice Library for sending actions to CoreWriter
// @dev Important! All weiAmounts should be converted to 6 decimals before calling this library
library CoreWriterLibrary {
    address public constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

    // CoreWriter encoding version. Hyperliquid currently only supports version 1
    bytes1 public constant CORE_WRITER_VERSION = hex"01";

    // 3-Byte Action IDs: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore
    bytes3 public constant TOKEN_DELEGATE = hex"000003";
    bytes3 public constant STAKING_DEPOSIT = hex"000004";
    bytes3 public constant STAKING_WITHDRAW = hex"000005";
    bytes3 public constant SPOT_SEND = hex"000006";
    bytes3 public constant ADD_API_WALLET = hex"000009";

    // @dev Sends a token delegate action to CoreWriter
    // @param validator The validator address to delegate or undelegate to
    // @param weiAmount The amount of wei to delegate or undelegate. Should be in 6 decimals
    // @param isUndelegate Whether to undelegate or delegate
    function tokenDelegate(address validator, uint64 weiAmount, bool isUndelegate) external {
        bytes memory encodedAction = abi.encode(validator, weiAmount, isUndelegate);
        _sendRawAction(CORE_WRITER_VERSION, TOKEN_DELEGATE, encodedAction);
    }

    // @dev Sends a staking deposit action to CoreWriter
    // @param weiAmount The amount of wei to deposit. Should be in 6 decimals
    function stakingDeposit(uint64 weiAmount) external {
        bytes memory encodedAction = abi.encode(weiAmount);
        _sendRawAction(CORE_WRITER_VERSION, STAKING_DEPOSIT, encodedAction);
    }

    // @dev Sends a staking withdraw action to CoreWriter
    // @param weiAmount The amount of wei to withdraw. Should be in 6 decimals
    function stakingWithdraw(uint64 weiAmount) external {
        bytes memory encodedAction = abi.encode(weiAmount);
        _sendRawAction(CORE_WRITER_VERSION, STAKING_WITHDRAW, encodedAction);
    }

    // @dev Sends a spot send action to CoreWriter
    // @param destination The destination address to send the spot to
    // @param token The token to send
    // @param weiAmount The amount of wei to send. Should be in 6 decimals
    function spotSend(address destination, uint64 token, uint64 weiAmount) external {
        bytes memory encodedAction = abi.encode(destination, token, weiAmount);
        _sendRawAction(CORE_WRITER_VERSION, SPOT_SEND, encodedAction);
    }

    // @dev Sends an add API wallet action to CoreWriter
    // @param apiWalletAddress The API wallet address to add
    // @param name The name of the API wallet. If empty, then this becomes the main API wallet / agent
    function addApiWallet(address apiWalletAddress, string calldata name) external {
        bytes memory encodedAction = abi.encode(apiWalletAddress, name);
        _sendRawAction(CORE_WRITER_VERSION, ADD_API_WALLET, encodedAction);
    }

    // @dev See https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore#action-encoding-details for more info
    function _sendRawAction(bytes1 version, bytes3 actionId, bytes memory encodedAction) internal {
        bytes memory data = new bytes(4 + encodedAction.length);
        // Byte 1: Encoding version
        data[0] = version;
        // Byte 2-4: Action ID
        data[1] = actionId[0];
        data[2] = actionId[1];
        data[3] = actionId[2];
        // Remaining bytes: Action encoding; the raw ABI encoding of a sequence of Solidity types
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        ICoreWriter(CORE_WRITER).sendRawAction(data);
    }
}
