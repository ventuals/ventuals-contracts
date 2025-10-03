// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {L1ReadLibrary} from "../libraries/L1ReadLibrary.sol";

interface IStakingVault {
    /// @notice Thrown when trying to transfer HYPE that exceeds the StakingVault balance.
    error InsufficientHYPEBalance();

    /// @notice Thrown if HYPE transfer fails to given recipient for specified amount.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown if the StakingVault is not activated on HyperCore.
    error CoreUserDoesNotExist(address account);

    /// @notice Thrown if a deposit cannot be made until the next block.
    error CannotDepositUntilNextBlock();

    /// @notice Thrown when a transfer to HyperCore cannot be made until the next block
    error CannotTransferToCoreUntilNextBlock();

    /// @notice Cannot read delegations until the next block
    error CannotReadDelegationUntilNextBlock();

    /// @notice Thrown if the validator is locked until a timestamp in the future.
    error StakeLockedUntilTimestamp(address validator, uint64 lockedUntilTimestamp);

    /// @notice Thrown if the validator is not whitelisted.
    error ValidatorNotWhitelisted(address validator);

    /// @notice Thrown if the from and to validators are the same.
    error RedelegateToSameValidator();

    /// @notice Thrown if the amount is 0.
    error ZeroAmount();

    /// @notice Emitted when HYPE is deposited into the vault (HyperEVM -> HyperEVM)
    event Deposit(address indexed sender, uint256 amount);

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    function HYPE_TOKEN_ID() external view returns (uint64);

    /// @dev Deposit HYPE into the vault (HyperEVM -> HyperEVM)
    /// @dev msg.value is the amount of HYPE to deposit (18 decimals)
    function deposit() external payable;

    /// @notice Deposits HYPE from spot on HyperCore to staking account, and delegates to the validator
    /// @param validator The address to delegate the HYPE to
    /// @param weiAmount The amount of wei to deposit&delegate (8 decimals) into the staking account
    function stake(address validator, uint64 weiAmount) external;

    /// @notice Undelegates HYPE from the validator and withdraws from the staking account to spot on HyperCore
    /// @param validator The address to undelegate the HYPE from
    /// @param weiAmount The amount of wei to undelegate&withdraw (8 decimals) from the staking account
    function unstake(address validator, uint64 weiAmount) external;

    /// @dev Redelegate HYPE from a validator to another validator
    /// @param fromValidator The validator address to undelegate from
    /// @param toValidator The validator address to delegate to
    /// @param weiAmount The amount of wei to delegate (8 decimals)
    function tokenRedelegate(address fromValidator, address toValidator, uint64 weiAmount) external;

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

    /// @dev Get the spot balance for the given token for the staking vault using HyperCore precompiles
    /// @param tokenId The token ID to get the spot balance for (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    function spotBalance(uint64 tokenId) external view returns (L1ReadLibrary.SpotBalance memory);

    /// @dev Get the balance of HYPE in the StakingVault contract (HyperEVM)
    /// @dev Truncates any precision beyond 8 decimals to prevent loss when transferring to HyperCore
    function evmBalance() external view returns (uint256);

    /// @dev Add a validator to the whitelist
    /// @param validator The validator to add to the whitelist
    function addValidator(address validator) external;

    /// @dev Remove a validator from the whitelist
    /// @param validator The validator to remove from the whitelist
    function removeValidator(address validator) external;
}
