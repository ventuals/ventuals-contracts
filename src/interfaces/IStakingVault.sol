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

    /// @notice Thrown when a transfer to HyperCore cannot be made until the next block
    error CannotTransferToCoreUntilNextBlock();

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

    /// @dev Get the delegator summary for the staking vault using HyperCore precompiles
    function delegatorSummary() external view returns (L1ReadLibrary.DelegatorSummary memory);

    /// @dev Check if the HYPE spot balance is safe to use
    /// @return isSafe The spot balance is unsafe if there was a HyperEVM -> HyperCore transfer earlier in the block.
    function isSpotBalanceSafe() external view returns (bool);

    /// @dev Get the HYPE spot balance using HyperCore precompiles
    /// @dev Check isSpotBalanceSafe() to ensure the spot balance is safe to use
    /// @return spotBalance The spot balance for the given token
    function spotBalance() external view returns (L1ReadLibrary.SpotBalance memory spotBalance);
}
