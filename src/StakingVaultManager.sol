// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base} from "./Base.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";
import {StructuredLinkedList} from "./libraries/StructuredLinkedList.sol";

contract StakingVaultManager is Base {
    using Converters for *;
    using StructuredLinkedList for StructuredLinkedList.List;

    /// @notice Thrown if HYPE transfer fails to given recipient for specified amount.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown if an amount of 0 is provided.
    error ZeroAmount();

    /// @notice Thrown if an amount exceeds the balance.
    error InsufficientBalance();

    /// @notice Thrown if the deposit amount is below the minimum deposit amount.
    error BelowMinimumDepositAmount();

    /// @notice Thrown if the caller is not authorized to perform the action.
    error NotAuthorized();

    /// @notice Thrown if the withdraw was cancelled.
    error WithdrawCancelled();

    /// @notice Thrown if the withdraw was already processed.
    error WithdrawProcessed();

    /// @notice Thrown if the withdraw was already claimed.
    error WithdrawClaimed();

    /// @notice Thrown if the withdraw is not claimable yet.
    error WithdrawUnclaimable();

    /// @notice Thrown if the account does not exist on HyperCore.
    error CoreUserDoesNotExist(address account);

    /// @notice Thrown if the batch is not ready to be processed.
    error BatchNotReady(uint256 readyAt);

    /// @notice Thrown if the batch is invalid.
    error InvalidBatch(uint256 batch);

    /// @notice Thrown if batch processing is paused.
    error BatchProcessingPaused();

    /// @notice Thrown if the account balance is less than the reserved HYPE for withdraws.
    error AccountBalanceLessThanReservedHypeForWithdraws();

    /// @notice Thrown if we don't have enough balance to finalize the batch.
    error NotEnoughBalance();

    /// @notice Thrown if we have more withdraw capacity when a batch is finalized.
    error HasMoreWithdrawCapacity();

    /// @notice Thrown if trying to finalize before a batch has been processed.
    error NothingToFinalize();

    /// @notice Thrown if trying to reset a batch that has not been processed.
    error NothingToReset();

    /// @notice Thrown if the number of withdrawals requested is too large
    error InvalidWithdrawRequest();

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
        /// @dev The account that requested the withdraw
        address account;
        /// @dev The amount of vHYPE to redeem (in 18 decimals)
        uint256 vhypeAmount;
        /// @dev The index of the batch this withdraw was assigned to
        /// @dev If the withdraw has not been assigned to a batch, this is set to type(uint256).max
        uint256 batchIndex;
        /// @dev Whether the withdraw has been cancelled
        bool cancelled;
        /// @dev Whether the withdraw has been claimed
        bool claimed;
    }

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// forge-lint: disable-next-line(mixed-case-variable)
    VHYPE public vHYPE;

    IStakingVault public stakingVault;

    /// @dev The validator to delegate and undelegate HYPE to
    address public validator;

    /// @dev The minimum amount of HYPE that needs to remain staked in the vault (in 18 decimals)
    uint256 public minimumStakeBalance;

    /// @dev The minimum amount of HYPE that can be deposited (in 18 decimals)
    uint256 public minimumDepositAmount;

    /// @dev Whether batch processing is paused
    bool public isBatchProcessingPaused;

    /// The timestamp at which the last batch was finalized.
    uint256 lastFinalizedBatchTime;

    /// @dev Batches of deposits and withdraws
    Batch[] private batches;

    /// @dev The current batch index
    uint256 public currentBatchIndex;

    /// @dev Auto-incrementing counter for withdraw IDs
    uint256 public nextWithdrawId;

    /// @dev The last withdraw ID that was processed
    uint256 public lastProcessedWithdrawId;

    /// @dev The withdraw queue as a linked list
    StructuredLinkedList.List private withdrawQueue;

    /// @dev Mapping from withdraw ID to withdraw data
    mapping(uint256 => Withdraw) private withdraws;

    /// @dev Mapping from account to withdraw IDs
    mapping(address => uint256[]) private accountWithdrawIds;

    /// @dev The total amount of withdrawn HYPE claimed (in 18 decimals)
    uint256 public totalHypeClaimed;

    /// @dev The total amount of HYPE processed. Gets adjusted if we retroactively apply a slash to a batch
    uint256 public totalHypeProcessed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint64 _hypeTokenId) {
        HYPE_TOKEN_ID = _hypeTokenId;

        _disableInitializers();
    }

    function initialize(
        address _roleRegistry,
        /// forge-lint: disable-next-line(mixed-case-variable)
        address _vHYPE,
        address _stakingVault,
        address _validator,
        uint256 _minimumStakeBalance,
        uint256 _minimumDepositAmount
    ) public initializer {
        __Base_init(_roleRegistry);

        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        validator = _validator;
        minimumStakeBalance = _minimumStakeBalance;
        minimumDepositAmount = _minimumDepositAmount;

        // Set batch processing to paused by default. OWNER will enable
        // it when batches are ready to be processed
        isBatchProcessingPaused = true;

        // Start at 1, because 0 is reserved for the head of the list
        nextWithdrawId = 1;
        lastProcessedWithdrawId = 0;
    }

    /// @notice Deposits HYPE into the vault, and mints the equivalent amount of vHYPE. Refunds any excess HYPE if only a partial deposit is made. Reverts if the vault is full.
    function deposit() external payable canDeposit whenNotPaused {
        uint256 amountToDeposit = msg.value;

        // Mint vHYPE
        // IMPORTANT: We need to make sure that we mint the vHYPE _before_ transferring the HYPE to the staking vault,
        // otherwise the exchange rate will be incorrect. We want the exchange rate to be calculated based on the total
        // HYPE in the vault _before_ the deposit
        uint256 amountToMint = HYPETovHYPE(amountToDeposit);
        vHYPE.mint(msg.sender, amountToMint);

        // Transfer HYPE to staking vault (HyperEVM -> HyperEVM)
        if (amountToDeposit > 0) {
            stakingVault.deposit{value: amountToDeposit}();
        }

        emit Deposit(msg.sender, amountToMint, amountToDeposit);
    }

    /// @notice Queues a withdraw from the vault
    /// @param vhypeAmount The amount of vHYPE to redeem (in 18 decimals)
    /// @return The ID of the withdraw
    function queueWithdraw(uint256 vhypeAmount) external whenNotPaused returns (uint256) {
        require(vhypeAmount > 0, ZeroAmount());

        // This contract escrows the vHYPE until the withdraw is processed
        bool success = vHYPE.transferFrom(msg.sender, address(this), vhypeAmount);
        require(success, TransferFailed(msg.sender, vhypeAmount));

        uint256 withdrawId = nextWithdrawId;

        // Store the withdraw data
        Withdraw memory withdraw = Withdraw({
            account: msg.sender,
            vhypeAmount: vhypeAmount,
            batchIndex: type(uint256).max, // Not assigned to a batch yet
            cancelled: false,
            claimed: false
        });
        withdraws[withdrawId] = withdraw;
        accountWithdrawIds[msg.sender].push(withdrawId);

        // Add to the end of the linked list
        withdrawQueue.pushBack(withdrawId);

        // Increment the withdraw ID counter
        nextWithdrawId++;

        emit QueueWithdraw(msg.sender, withdrawId, withdraw);

        return withdrawId;
    }

    /// @notice Claims a withdraw
    /// @param withdrawId The ID of the withdraw to claim
    /// @param destination The address to send the HYPE to
    function claimWithdraw(uint256 withdrawId, address destination) public whenNotPaused {
        Withdraw storage withdraw = withdraws[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(!withdraw.cancelled, WithdrawCancelled());
        require(!withdraw.claimed, WithdrawClaimed());

        Batch memory batch = batches[withdraw.batchIndex];
        require(block.timestamp > batch.finalizedAt + 7 days, WithdrawUnclaimable()); // TODO: Should we add a buffer?

        uint256 withdrawExchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;
        uint256 hypeAmount = _vHYPEtoHYPE(withdraw.vhypeAmount, withdrawExchangeRate);

        // Note: If the destination account doesn't exist on HyperCore, the spotSend will silently fail
        // and the HYPE will not actually be sent. We check the account exists before making the call,
        // so users don't lose their HYPE if their HyperCore account doesn't exist.
        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(destination);
        require(coreUserExists.exists, CoreUserDoesNotExist(destination));

        // Note: We don't expect to run into this case, but we're adding this check for safety. The spotSend call will
        // silently fail if the vault doesn't have enough HYPE, so we check the balance before making the call.
        L1ReadLibrary.SpotBalance memory spotBalance = L1ReadLibrary.spotBalance(address(stakingVault), HYPE_TOKEN_ID);
        require(spotBalance.total.to18Decimals() >= hypeAmount, InsufficientBalance());

        // NOTE: We don't need to worry about transfer to Core timings here, because claimable HYPE is excluded
        // from the total balance (via `totalHypeProcessed`)
        stakingVault.spotSend(destination, HYPE_TOKEN_ID, hypeAmount.to8Decimals());

        withdraw.claimed = true;
        totalHypeClaimed += hypeAmount;

        emit ClaimWithdraw(msg.sender, withdrawId, withdraw);
    }

    /// @notice Claims multiple withdraws
    /// @param withdrawIds The IDs of the withdraws to claim
    /// @param destination The address to send the HYPE to
    function batchClaimWithdraws(uint256[] calldata withdrawIds, address destination) public whenNotPaused {
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            claimWithdraw(withdrawIds[i], destination);
        }
    }

    /// @notice Cancels a withdraw. A withdraw can only be cancelled if it has not been processed yet.
    /// @param withdrawId The ID of the withdraw to cancel
    function cancelWithdraw(uint256 withdrawId) external whenNotPaused {
        Withdraw storage withdraw = withdraws[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(!withdraw.cancelled, WithdrawCancelled());
        require(withdraw.batchIndex == type(uint256).max, WithdrawProcessed()); // Can only cancel unprocessed withdraws

        // Remove from the linked list
        withdrawQueue.remove(withdrawId);

        // Set cancelled to true
        withdraw.cancelled = true;

        // Refund vHYPE
        uint256 vhypeAmount = withdraw.vhypeAmount;
        bool success = vHYPE.transfer(msg.sender, vhypeAmount);
        require(success, TransferFailed(msg.sender, vhypeAmount));

        emit CancelWithdraw(msg.sender, withdrawId, withdraw);
    }

    /// @notice Processes a batch of withdraws
    /// @param numWithdrawals The number of withdraws to process
    function processBatch(uint256 numWithdrawals) external whenNotPaused whenBatchProcessingNotPaused {
        Batch memory batch = _fetchBatch();

        uint256 hypeProcessed = _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);
        uint256 balance = totalBalance();
        uint256 withdrawCapacityAvailable = 0;
        if (balance >= minimumStakeBalance + hypeProcessed) {
            withdrawCapacityAvailable = balance - minimumStakeBalance - hypeProcessed;
        }

        // Iterate until we:
        // - Hit the withdraw capacity, or
        // - Process the requested number of withdraws, or
        // - Have no more withdraws to process
        while (withdrawCapacityAvailable > 0 && numWithdrawals > 0) {
            // Get the next withdraw to process
            (bool hasNextNode, uint256 nextNodeId) = withdrawQueue.getNextNode(lastProcessedWithdrawId);
            if (!hasNextNode) {
                break;
            }

            Withdraw storage withdraw = withdraws[nextNodeId];

            uint256 expectedHypeAmount = _vHYPEtoHYPE(withdraw.vhypeAmount, batch.snapshotExchangeRate);
            if (expectedHypeAmount > withdrawCapacityAvailable) {
                break;
            }

            // Update capacity available
            withdrawCapacityAvailable -= expectedHypeAmount;

            // Count towards the number processed in this call
            numWithdrawals--;

            // Update batch metrics (in memory)
            if (!withdraw.cancelled) {
                batch.vhypeProcessed += withdraw.vhypeAmount;
            }

            // Update withdrawal information
            withdraw.batchIndex = currentBatchIndex;

            // Move to next withdraw in the linked list
            lastProcessedWithdrawId = nextNodeId;
        }

        // Checkpoint the batch to storage
        _checkpointBatch(batch);
    }

    function _fetchBatch() internal view returns (Batch memory batch) {
        if (currentBatchIndex == batches.length) {
            // Initialize a new batch at the current index
            // Only enforce timing restriction if this is not the first batch
            if (lastFinalizedBatchTime != 0) {
                require(
                    block.timestamp > lastFinalizedBatchTime + 1 days, BatchNotReady(lastFinalizedBatchTime + 1 days)
                ); // TODO: Should we add a buffer?
            }
            uint256 snapshotExchangeRate = exchangeRate();

            batch = Batch({
                vhypeProcessed: 0,
                snapshotExchangeRate: snapshotExchangeRate,
                slashedExchangeRate: 0,
                slashed: false,
                finalizedAt: 0
            });
        } else {
            // Use the current batch
            batch = batches[currentBatchIndex];
        }
        return batch;
    }

    /// @dev stores the batch, either by appending a new one or by overwriting the current batch.
    function _checkpointBatch(Batch memory batch) internal {
        if (currentBatchIndex == batches.length) {
            batches.push(batch);
        } else {
            batches[currentBatchIndex] = batch;
        }
    }

    /// @notice Finalizes the current batch.
    function finalizeBatch() external whenNotPaused whenBatchProcessingNotPaused {
        // Check if we have a batch to finalize
        require(currentBatchIndex < batches.length, NothingToFinalize());

        Batch memory batch = batches[currentBatchIndex];

        // Check if we can finalize the batch. This will revert if we cannot finalize the batch.
        _canFinalizeBatch(batch);

        uint256 depositsInBatch = address(stakingVault).balance;
        uint256 withdrawsInBatch = _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);

        // Update totalHypeProcessed to track reserved HYPE for withdrawals
        totalHypeProcessed += withdrawsInBatch;

        // Save the timestamp that the batch was finalized
        batches[currentBatchIndex].finalizedAt = block.timestamp;
        lastFinalizedBatchTime = block.timestamp;

        // Increment the batch index
        currentBatchIndex++;

        // Burn the escrowed vHYPE (burn from this contract's balance)
        vHYPE.burn(batch.vhypeProcessed);

        // Always transfer the full deposit amount to HyperCore spot
        if (depositsInBatch > 0) {
            stakingVault.transferHypeToCore(depositsInBatch);
        }

        // Net out the deposits and withdraws in the batch
        if (depositsInBatch > withdrawsInBatch) {
            // All withdraws are covered by deposits

            // Stake the excess HYPE
            uint256 amountToStake = depositsInBatch - withdrawsInBatch;
            stakingVault.stake(validator, amountToStake.to8Decimals());
        } else if (depositsInBatch < withdrawsInBatch) {
            // Not enough deposits to cover all withdraws; we need to withdraw some HYPE from the staking vault

            // Unstake the amount not covered by deposits from the staking vault
            uint256 amountToUnstake = withdrawsInBatch - depositsInBatch;
            stakingVault.unstake(validator, amountToUnstake.to8Decimals());
        }
    }

    function _canFinalizeBatch(Batch memory batch) internal view {
        require(currentBatchIndex + 1 == batches.length, NothingToFinalize());

        uint256 hypeProcessed = _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);

        uint256 balance = totalBalance();

        // Make sure we have enough balance to cover the withdraws
        if (hypeProcessed > 0) {
            require(balance >= minimumStakeBalance + hypeProcessed, NotEnoughBalance());
        }

        // If we've processed all withdraws, we can finalize the batch
        if (lastProcessedWithdrawId == withdrawQueue.getTail()) {
            return;
        }

        // If we haven't processed all withdraws, make sure we've processed all withdraws that we
        // have capacity for
        if (balance >= minimumStakeBalance + hypeProcessed) {
            uint256 withdrawCapacityRemaining = balance - minimumStakeBalance - hypeProcessed;
            (, uint256 nextWithdrawIdToProcess) = withdrawQueue.getNextNode(lastProcessedWithdrawId);
            Withdraw memory withdraw = withdraws[nextWithdrawIdToProcess];
            uint256 expectedHypeAmount = _vHYPEtoHYPE(withdraw.vhypeAmount, batch.snapshotExchangeRate);
            require(expectedHypeAmount > withdrawCapacityRemaining, HasMoreWithdrawCapacity());
        }
    }

    /// @notice Returns the batch at the given index
    /// @param index The index of the batch to return
    function getBatch(uint256 index) public view returns (Batch memory) {
        return batches[index];
    }

    /// @notice Returns the length of the batches array
    function getBatchesLength() public view returns (uint256) {
        return batches.length;
    }

    /// @notice Returns the withdraw at the given ID
    /// @param withdrawId The ID of the withdraw to return
    function getWithdraw(uint256 withdrawId) public view returns (Withdraw memory) {
        return withdraws[withdrawId];
    }

    /// @notice Returns the size of the withdraw queue (number of withdraws in the linked list)
    function getWithdrawQueueLength() public view returns (uint256) {
        return withdrawQueue.sizeOf();
    }

    /// @notice Calculates the vHYPE amount for a given HYPE amount, based on the exchange rate
    /// @param hypeAmount The HYPE amount to convert (in 18 decimals)
    /// @return The vHYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function)
    function HYPETovHYPE(uint256 hypeAmount) public view returns (uint256) {
        return _HYPETovHYPE(hypeAmount, exchangeRate());
    }

    /// @notice Calculates the vHYPE amount for a given HYPE amount, based on the provided exchange rate
    /// @param hypeAmount The HYPE amount to convert (in 18 decimals)
    /// @param _exchangeRate The exchange rate to use (in 18 decimals)
    /// @return The vHYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function)
    function _HYPETovHYPE(uint256 hypeAmount, uint256 _exchangeRate) internal pure returns (uint256) {
        if (_exchangeRate == 0) {
            return 0;
        }
        return Math.mulDiv(hypeAmount, 1e18, _exchangeRate);
    }

    /// @notice Calculates the HYPE amount for a given vHYPE amount, based on the exchange rate
    /// @param vHYPEAmount The vHYPE amount to convert (in 18 decimals)
    /// @return The HYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function, mixed-case-variable)
    function vHYPEtoHYPE(uint256 vHYPEAmount) public view returns (uint256) {
        return _vHYPEtoHYPE(vHYPEAmount, exchangeRate());
    }

    /// @notice Calculates the HYPE amount for a given vHYPE amount, based on the provided exchange rate
    /// @param vHYPEAmount The vHYPE amount to convert (in 18 decimals)
    /// @param _exchangeRate The exchange rate to use (in 18 decimals)
    /// @return The HYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function, mixed-case-variable)
    function _vHYPEtoHYPE(uint256 vHYPEAmount, uint256 _exchangeRate) internal pure returns (uint256) {
        if (_exchangeRate == 0) {
            return 0;
        }
        return Math.mulDiv(vHYPEAmount, _exchangeRate, 1e18);
    }

    /// @notice Returns the exchange rate of HYPE to vHYPE (in 18 decimals)
    /// @dev Ratio of total HYPE in the staking vault to vHYPE
    function exchangeRate() public view returns (uint256) {
        uint256 balance = totalBalance();
        uint256 totalSupply = vHYPE.totalSupply();

        // If we have no vHYPE in circulation, the exchange rate is 1
        if (totalSupply == 0) {
            return 1e18;
        }

        // If we have no HYPE in the vault, the exchange rate is 0
        if (balance == 0) {
            return 0;
        }

        return Math.mulDiv(balance, 1e18, totalSupply);
    }

    /// @notice Returns the total HYPE balance that belongs to the vault (in 18 decimals)
    function totalBalance() public view returns (uint256) {
        // EVM + Spot + Staking account balances
        uint256 accountBalances = stakingAccountBalance() + spotAccountBalance() + address(stakingVault).balance;

        // The total amount of HYPE that is reserved to be returned to users for withdraws, but is still in
        // under the StakingVault accounts because they have not finished processing or been claimed
        uint256 reservedHypeForWithdraws = totalHypeProcessed - totalHypeClaimed;

        // This might happen right after a slash, before we're able to adjust the slashed exchange rate for the
        // processed withdraws that are waiting for the 7-day withdraw period to pass. In practice, we would
        // pause the contract in the case of a slash, but there could be a small window of time right after a
        // slash where this could happen. So we throw an explicit error in this case.
        require(accountBalances >= reservedHypeForWithdraws, AccountBalanceLessThanReservedHypeForWithdraws());

        return accountBalances - reservedHypeForWithdraws;
    }

    /// @notice Total HYPE balance in the staking vault's staking account balance (in 18 decimals)
    /// @dev Uses L1Read precompiles to get the delegator summary for the staking vault from HyperCore
    function stakingAccountBalance() public view returns (uint256) {
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        return delegatorSummary.delegated.to18Decimals() + delegatorSummary.undelegated.to18Decimals()
            + delegatorSummary.totalPendingWithdrawal.to18Decimals();
    }

    /// @notice Total HYPE balance in the staking vault's spot account balance (in 18 decimals)
    /// @dev Uses L1Read precompiles to get the spot balance for the staking vault from HyperCore
    function spotAccountBalance() public view returns (uint256) {
        L1ReadLibrary.SpotBalance memory spotBalance = stakingVault.spotBalance(HYPE_TOKEN_ID);
        return spotBalance.total.to18Decimals();
    }

    /// @notice Returns the withdraws for a given account
    /// @param account The account to get withdraws for
    function getAccountWithdraws(address account) public view returns (Withdraw[] memory) {
        uint256[] memory withdrawIds = accountWithdrawIds[account];
        Withdraw[] memory _withdraws = new Withdraw[](withdrawIds.length);
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            _withdraws[i] = withdraws[withdrawIds[i]];
        }
        return _withdraws;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Owner Actions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the minimum stake balance (in 18 decimals)
    /// @dev Minimum stake balance is the total amount of HYPE that must remain staked in the vault
    function setMinimumStakeBalance(uint256 _minimumStakeBalance) external onlyOwner {
        minimumStakeBalance = _minimumStakeBalance;
    }

    /// @notice Switches the validator to delegate HYPE to
    /// @param newValidator The new validator
    function switchValidator(address newValidator) external onlyOwner {
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        stakingVault.tokenRedelegate(validator, newValidator, delegatorSummary.delegated);

        validator = newValidator;
    }

    /// @notice Sets the minimum deposit amount (in 18 decimals)
    /// @param _minimumDepositAmount The minimum deposit amount (in 18 decimals)
    function setMinimumDepositAmount(uint256 _minimumDepositAmount) external onlyOwner {
        minimumDepositAmount = _minimumDepositAmount;
    }

    /// @notice Sets whether batch processing is paused
    /// @param _isBatchProcessingPaused Whether batch processing is paused
    function setBatchProcessingPaused(bool _isBatchProcessingPaused) external onlyOwner {
        isBatchProcessingPaused = _isBatchProcessingPaused;
    }

    /// @notice Resets the current batch, undoing all withdrawals that have been processed
    /// @dev This can only be called on a batch that has not been finalized yet
    function resetBatch(uint256 numWithdrawals) external onlyOwner {
        // Can only reset if there's a batch to reset
        require(currentBatchIndex < batches.length, NothingToReset());
        require(lastProcessedWithdrawId > 0, NothingToReset());

        Batch storage batch = batches[currentBatchIndex];

        // Can only reset a batch that hasn't been finalized
        require(batch.finalizedAt == 0, InvalidBatch(currentBatchIndex));

        while (numWithdrawals > 0) {
            Withdraw storage withdraw = withdraws[lastProcessedWithdrawId];
            if (withdraw.batchIndex == currentBatchIndex) {
                // If the withdraw is part of the current batch

                // Update the withdraw to unassign from batch
                withdraw.batchIndex = type(uint256).max;

                // Remove the vHYPE processed from the batch
                batch.vhypeProcessed -= withdraw.vhypeAmount;

                // Move to the previous withdraw in the queue
                (bool prevNodeExists, uint256 prevNodeId) = withdrawQueue.getPreviousNode(lastProcessedWithdrawId);
                if (prevNodeExists) {
                    lastProcessedWithdrawId = prevNodeId; // Previous withdraw exists
                } else {
                    lastProcessedWithdrawId = 0; // Back at the head of the queue
                    break;
                }

                numWithdrawals--;
            } else if (withdraw.batchIndex != type(uint256).max) {
                // We've reached a withdrawal that's part of an earlier batch
                // No need to continue since we've reset all withdrawals in the current batch
                break;
            }
        }
    }

    /// @notice Finalizes the reset batch, removing it from the array
    /// @dev This can only be called on a batch that has been reset to 0 vHYPE
    function finalizeResetBatch() external onlyOwner {
        require(currentBatchIndex < batches.length, NothingToFinalize());
        Batch storage batch = batches[currentBatchIndex];

        // Can only finalize a batch that hasn't been finalized, and has been reset to 0 vHYPE
        require(batch.finalizedAt == 0, InvalidBatch(currentBatchIndex));
        require(batch.vhypeProcessed == 0, InvalidBatch(currentBatchIndex));

        // Remove the batch entirely
        batches.pop();
    }

    /// @notice Applies a slash to a batch
    /// @param batchIndex The index of the batch to apply the slash to
    /// @param slashedExchangeRate The new exchange rate that should be applied to the batch (in 18 decimals)
    function applySlash(uint256 batchIndex, uint256 slashedExchangeRate) external onlyOwner {
        require(batchIndex < batches.length, InvalidBatch(batchIndex));
        Batch storage batch = batches[batchIndex];

        uint256 oldExchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;

        // Only adjust totalHypeProcessed if the batch has been finalized
        if (batch.finalizedAt > 0) {
            totalHypeProcessed -= _vHYPEtoHYPE(batch.vhypeProcessed, oldExchangeRate);
            totalHypeProcessed += _vHYPEtoHYPE(batch.vhypeProcessed, slashedExchangeRate);
        }

        batch.slashedExchangeRate = slashedExchangeRate;
        batch.slashed = true;
    }

    /// @notice Execute an emergency staking withdraw
    /// @dev Immediately undelegates HYPE and initiates a staking withdraw
    /// @dev Amount will be available in the StakingVault's spot account balance after 7 days.
    /// @param amount Amount to withdraw (in 18 decimals)
    /// @param purpose Description of withdrawal purpose
    function emergencyStakingWithdraw(uint256 amount, string calldata purpose) external onlyOwner {
        // Immediately undelegate HYPE
        // Queue a staking withdrawal, subject to the 7-day withdrawal queue. Amount will be available in
        // the StakingVault's spot account balance after 7 days.
        stakingVault.unstake(validator, amount.to8Decimals());
        emit EmergencyStakingWithdraw(msg.sender, amount, purpose);
    }

    /// @notice Execute an emergency staking deposit (from HyperCore Spot)
    /// @dev Immediately delegates HYPE to the validator
    /// @param amount Amount to deposit (in 18 decimals)
    /// @param purpose Description of deposit purpose
    function emergencyStakingDeposit(uint256 amount, string calldata purpose) external onlyOwner {
        // NOTE: We don't check the spot balance here for simplicity. In practice, we'll only call this
        // to rectify the HyperCore Spot balance after a slash, which would generally happen when the
        // contract is paused and only owner functions are available. In the worst case, we don't have
        // enough HYPE in HyperCore Spot to perform a staking deposit, and these two CoreWriter calls
        // will just fail silently, and no HYPE will be lost.
        stakingVault.stake(validator, amount.to8Decimals());
        emit EmergencyStakingDeposit(msg.sender, amount, purpose);
    }

    modifier canDeposit() {
        _canDeposit();
        _;
    }

    function _canDeposit() internal view {
        require(msg.value >= minimumDepositAmount, BelowMinimumDepositAmount());
    }

    modifier whenBatchProcessingNotPaused() {
        _whenBatchProcessingNotPaused();
        _;
    }

    function _whenBatchProcessingNotPaused() internal view {
        require(!isBatchProcessingPaused, BatchProcessingPaused());
    }
}
