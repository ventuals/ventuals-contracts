// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

interface IStakingVaultManager {
    /// @notice Thrown if HYPE transfer fails to given recipient for specified amount.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown if an amount of 0 is provided.
    error ZeroAmount();

    /// @notice Thrown if the deposit amount is below the minimum deposit amount.
    error BelowMinimumDepositAmount();

    /// @notice Thrown if the withdraw amount is below the minimum withdraw amount.
    error BelowMinimumWithdrawAmount();

    /// @notice Thrown if the caller is not authorized to perform the action.
    error NotAuthorized();

    /// @notice Thrown if the withdraw was cancelled.
    error WithdrawCancelled();

    /// @notice Thrown if the withdraw was not processed.
    error WithdrawNotProcessed();

    /// @notice Thrown if the withdraw was already processed.
    error WithdrawProcessed();

    /// @notice Thrown if the withdraw was already claimed.
    error WithdrawClaimed();

    /// @notice Thrown if the withdraw is not claimable yet.
    error WithdrawUnclaimable();

    /// @notice Thrown if the batch is not ready to be processed.
    error BatchNotReady(uint256 readyAt);

    /// @notice Thrown if the batch is invalid.
    error InvalidBatch(uint256 batch);

    /// @notice Thrown if the batch cannot be slashed.
    error CannotSlashBatchOutsideSlashWindow(uint256 batch);

    /// @notice Thrown if batch processing is paused.
    error BatchProcessingPaused();

    /// @notice Thrown if the account balance is less than the reserved HYPE for withdraws.
    error AccountBalanceLessThanReservedHypeForWithdraws();

    /// @notice Thrown if we don't have enough balance to finalize the batch.
    error NotEnoughBalance();

    /// @notice Thrown if the updated minimum stake balance is too large.
    error MinimumStakeBalanceTooLarge();

    /// @notice Thrown if we have more withdraw capacity when a batch is finalized.
    error HasMoreWithdrawCapacity();

    /// @notice Thrown if trying to finalize before a batch has been processed.
    error NothingToFinalize();

    /// @notice Thrown if trying to reset a batch that has not been processed.
    error NothingToReset();

    /// @notice Emitted when HYPE is deposited into the vault
    /// @param depositor The address that deposited the HYPE
    /// @param minted The amount of vHYPE minted (in 18 decimals)
    /// @param deposited The amount of HYPE deposited (in 18 decimals)
    event Deposit(address indexed depositor, uint256 minted, uint256 deposited);

    /// @notice Emitted when a withdraw is queued
    /// @param account The address that queued the withdraw
    /// @param withdrawId The ID of the withdraw
    /// @param withdraw The withdraw data
    event QueueWithdraw(address indexed account, uint256 withdrawId, Withdraw withdraw);

    /// @notice Emitted when a withdraw is cancelled
    /// @param account The address that cancelled the withdraw
    /// @param withdrawId The ID of the withdraw
    /// @param withdraw The withdraw data
    event CancelWithdraw(address indexed account, uint256 withdrawId, Withdraw withdraw);

    /// @notice Emitted when a withdraw is processed
    /// @param account The address that processed the withdraw
    /// @param withdrawId The ID of the withdraw
    /// @param withdraw The withdraw data
    event ProcessWithdraw(address indexed account, uint256 withdrawId, Withdraw withdraw);

    /// @notice Emitted when a withdraw is claimed
    /// @param account The address that claimed the withdraw
    /// @param withdrawId The ID of the withdraw
    /// @param withdraw The withdraw data
    event ClaimWithdraw(address indexed account, uint256 withdrawId, Withdraw withdraw);

    /// @notice Emitted when a batch is processed
    /// @param batchId The ID of the batch
    /// @param batch The batch data
    event ProcessBatch(uint256 batchId, Batch batch);

    /// @notice Emitted when a batch is finalized
    /// @param batchId The ID of the batch
    /// @param batch The batch data
    event FinalizeBatch(uint256 batchId, Batch batch);

    /// @notice Emitted when a batch is slashed
    /// @param batchIndex The index of the batch
    /// @param slashedExchangeRate The exchange rate after the slash
    event ApplySlash(uint256 batchIndex, uint256 slashedExchangeRate);

    /// @notice Emitted when a batch is reset
    /// @param batchIndex The index of the batch
    /// @param batch The batch data
    event ResetBatch(uint256 batchIndex, Batch batch);

    /// @notice Emitted when a batch is finalized after being reset
    /// @param batchIndex The index of the batch
    /// @param batch The batch data
    event FinalizeResetBatch(uint256 batchIndex, Batch batch);

    /// @notice Emitted when an emergency staking withdraw is executed
    /// @param sender The address that executed the emergency withdraw
    /// @param amount The amount of HYPE withdrawn
    /// @param purpose The purpose of the withdrawal
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);

    /// @notice Emitted when an emergency staking deposit is executed
    /// @param sender The address that executed the emergency deposit
    /// @param amount The amount of HYPE deposited
    /// @param purpose The purpose of the deposit
    event EmergencyStakingDeposit(address indexed sender, uint256 amount, string purpose);

    /// @dev A batch of withdraws that are processed together
    struct Batch {
        /// @dev The total amount of withdraws processed in this batch (vHYPE; in 18 decimals)
        uint256 vhypeProcessed;
        /// @dev The exchange rate at the time the batch was processed (in 18 decimals)
        uint256 snapshotExchangeRate;
        /// @dev The exchange rate if a slash was applied to the batch (in 18 decimals)
        uint256 slashedExchangeRate;
        /// @dev Whether the batch was slashed
        bool slashed;
        /// @dev The timestamp at which the batch was finalized.
        uint256 finalizedAt;
    }

    /// @dev A withdraw from the vault
    struct Withdraw {
        /// @dev The ID of the withdraw
        uint256 id;
        /// @dev The account that requested the withdraw
        address account;
        /// @dev The amount of vHYPE to redeem (in 18 decimals)
        uint256 vhypeAmount;
        /// @dev The timestamp at which the withdraw was queued
        uint256 queuedAt;
        /// @dev The index of the batch this withdraw was assigned to
        /// @dev If the withdraw has not been assigned to a batch, this is set to type(uint256).max
        uint256 batchIndex;
        /// @dev The timestamp at which the withdraw was cancelled. 0 if not cancelled
        uint256 cancelledAt;
        /// @dev The timestamp at which the withdraw was claimed. 0 if not claimed
        uint256 claimedAt;
    }

    /// @notice Deposits HYPE into the vault, and mints the equivalent amount of vHYPE.
    function deposit() external payable;

    /// @notice Queues a withdraw from the vault
    /// @param vhypeAmount The amount of vHYPE to redeem (in 18 decimals)
    /// @return The IDs of the withdraws
    function queueWithdraw(uint256 vhypeAmount) external returns (uint256[] memory);

    /// @notice Claims a withdraw
    /// @param withdrawId The ID of the withdraw to claim
    /// @param destination The address to send the HYPE to
    function claimWithdraw(uint256 withdrawId, address destination) external;

    /// @notice Claims multiple withdraws
    /// @param withdrawIds The IDs of the withdraws to claim
    /// @param destination The address to send the HYPE to
    function batchClaimWithdraws(uint256[] calldata withdrawIds, address destination) external;

    /// @notice Cancels a withdraw. A withdraw can only be cancelled if it has not been processed yet.
    /// @param withdrawId The ID of the withdraw to cancel
    function cancelWithdraw(uint256 withdrawId) external;

    /// @notice Processes a batch of withdraws
    /// @param numWithdrawals The number of withdraws to process
    /// @return The number of withdraws processed
    function processBatch(uint256 numWithdrawals) external returns (uint256);

    /// @notice Finalizes the current batch.
    function finalizeBatch() external;

    /// @notice Returns the batch at the given index
    /// @param index The index of the batch to return
    function getBatch(uint256 index) external view returns (Batch memory);

    /// @notice Returns the length of the batches array
    function getBatchesLength() external view returns (uint256);

    /// @notice Returns the withdraw at the given ID
    /// @param withdrawId The ID of the withdraw to return
    function getWithdraw(uint256 withdrawId) external view returns (Withdraw memory);

    /// @notice Returns the size of the withdraw queue (number of withdraws in the linked list)
    function getWithdrawQueueLength() external view returns (uint256);

    /// @notice Returns the amount of HYPE for the given withdraw ID
    /// @param withdrawId The ID of the withdraw to return
    function getWithdrawAmount(uint256 withdrawId) external view returns (uint256);

    /// @notice Returns the time at which the withdraw will be claimable
    /// @dev Returns `type(uint256).max` if the withdraw has not been processed yet
    /// @param withdrawId The ID of the withdraw to return
    function getWithdrawClaimableAt(uint256 withdrawId) external view returns (uint256);

    /// @notice Calculates the vHYPE amount for a given HYPE amount, based on the exchange rate
    /// @param hypeAmount The HYPE amount to convert (in 18 decimals)
    /// @return The vHYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function)
    function HYPETovHYPE(uint256 hypeAmount) external view returns (uint256);

    /// @notice Calculates the HYPE amount for a given vHYPE amount, based on the exchange rate
    /// @param vHYPEAmount The vHYPE amount to convert (in 18 decimals)
    /// @return The HYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function, mixed-case-variable)
    function vHYPEtoHYPE(uint256 vHYPEAmount) external view returns (uint256);

    /// @notice Returns the exchange rate of HYPE to vHYPE (in 18 decimals)
    /// @dev Ratio of total HYPE in the staking vault to vHYPE
    function exchangeRate() external view returns (uint256);

    /// @notice Returns the total HYPE balance that belongs to the vault (in 18 decimals)
    function totalBalance() external view returns (uint256);

    /// @notice Returns the withdraws for a given account
    /// @param account The account to get withdraws for
    function getAccountWithdraws(address account) external view returns (Withdraw[] memory);

    /// @notice Sets the minimum stake balance (in 18 decimals)
    /// @param _minimumStakeBalance The minimum stake balance (in 18 decimals)
    function setMinimumStakeBalance(uint256 _minimumStakeBalance) external;

    /// @notice Enables full withdrawal by setting the minimum stake balance to 0
    /// @dev This is used in the event the LST is wind down
    function windDown() external;
}
