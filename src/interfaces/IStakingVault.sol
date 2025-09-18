// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {L1ReadLibrary} from "../libraries/L1ReadLibrary.sol";

interface IStakingVault {
    /// @notice Thrown when trying to transfer HYPE that exceeds the StakingVault balance.
    error InsufficientHYPEBalance();

    /// @notice Thrown if HYPE transfer fails to given recipient for specified amount.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown if the StakingVault is not activated on HyperCore.
    error NotActivatedOnHyperCore();

    /// @notice Emitted when HYPE is deposited into the vault (HyperEVM -> HyperEVM)
    event Deposit(address indexed sender, uint256 amount);

    /// @dev Deposit HYPE into the vault (HyperEVM -> HyperEVM)
    /// @dev msg.value is the amount of HYPE to deposit (18 decimals)
    function deposit() external payable;

    /// @dev Deposit HYPE from spot to staking account on HyperCore
    /// @param weiAmount The amount of wei to deposit (8 decimals)
    function stakingDeposit(uint64 weiAmount) external;

    /// @dev Withdraw HYPE from staking account to spot on HyperCore
    /// @param weiAmount The amount of wei to withdraw (8 decimals)
    function stakingWithdraw(uint64 weiAmount) external;

    /// @dev Delegate or undelegate HYPE to a validator
    /// @param validator The validator address to delegate or undelegate to
    /// @param weiAmount The amount of wei to delegate or undelegate (8 decimals)
    /// @param isUndelegate Whether to undelegate or delegate
    function tokenDelegate(address validator, uint64 weiAmount, bool isUndelegate) external;

    /// @dev Transfer a token from Core spot. See https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/hypercore-less-than-greater-than-hyperevm-transfers for more info
    /// @param destination The destination address to send the token to
    /// @param token The token to send
    /// @param weiAmount The amount of wei to send. Should be in HyperCore decimals (e.g. 8 decimals for HYPE)
    function spotSend(address destination, uint64 token, uint64 weiAmount) external;

    /// @dev Add an API wallet
    /// @param apiWalletAddress The API wallet address to add
    /// @param name The name of the API wallet. If empty, then this becomes the main API wallet / agent
    function addApiWallet(address apiWalletAddress, string calldata name) external;

    /// @dev Transfer HYPE to from HyperEVM to HyperCore
    /// @param amount The amount of HYPE to transfer (18 decimals)
    function transferHypeToCore(uint256 amount) external;

    /// @dev Transfer HYPE to the recipient (HyperEVM to HyperEVM)
    /// @param recipient The recipient address to transfer HYPE to
    /// @param amount The amount of HYPE to transfer (18 decimals)
    function transferHype(address payable recipient, uint256 amount) external;

    /// @dev Get the delegator summary for the staking vault using HyperCore precompiles
    function delegatorSummary() external view returns (L1ReadLibrary.DelegatorSummary memory);

    /// @dev Get the spot balance for the given token for the staking vault using HyperCore precompiles
    /// @param tokenId The token ID to get the spot balance for (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    function spotBalance(uint64 tokenId) external view returns (L1ReadLibrary.SpotBalance memory);
}
