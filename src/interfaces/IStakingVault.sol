// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IStakingVault {
    /// @dev Deposit HYPE from spot to staking account on HyperCore. The payable amount will be converted to 8 decimals before sending to CoreWriter
    function stakingDeposit() external payable;

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
}
