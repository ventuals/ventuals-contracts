// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {IStakingVaultManager} from "./interfaces/IStakingVaultManager.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base} from "./Base.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";
import {StructuredLinkedList} from "./libraries/StructuredLinkedList.sol";

contract StakingVaultManager is Base, IStakingVaultManager {
    using Converters for *;
    using StructuredLinkedList for StructuredLinkedList.List;

    /// forge-lint: disable-next-line(mixed-case-variable)
    VHYPE public vHYPE;

    IStakingVault public stakingVault;

    /// @dev The validator to delegate and undelegate HYPE to
    address public validator;

    /// @dev The minimum amount of HYPE that needs to remain staked in the vault (in 18 decimals)
    uint256 public minimumStakeBalance;

    /// @dev The minimum amount of HYPE that can be deposited (in 18 decimals)
    uint256 public minimumDepositAmount;

    /// @dev The minimum amount of HYPE that can be withdrawn (in 18 decimals)
    uint256 public minimumWithdrawAmount;

    /// @dev The maximum amount of HYPE that can be withdrawn (in 18 decimals)
    uint256 public maximumWithdrawAmount;

    /// @dev Whether batch processing is paused
    bool public isBatchProcessingPaused;

    /// @dev The timestamp at which the last batch was finalized.
    uint256 public lastFinalizedBatchTime;

    /// @dev The additional time to wait after a batch is finalized before it can be claimed
    uint256 public claimWindowBuffer;

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
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _roleRegistry,
        /// forge-lint: disable-next-line(mixed-case-variable)
        address _vHYPE,
        address _stakingVault,
        address _validator,
        uint256 _minimumStakeBalance,
        uint256 _minimumDepositAmount,
        uint256 _minimumWithdrawAmount,
        uint256 _maximumWithdrawAmount
    ) public initializer {
        __Base_init(_roleRegistry);

        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        validator = _validator;
        minimumStakeBalance = _minimumStakeBalance;
        minimumDepositAmount = _minimumDepositAmount;
        minimumWithdrawAmount = _minimumWithdrawAmount;
        maximumWithdrawAmount = _maximumWithdrawAmount;

        // Set batch processing to paused by default. OWNER will enable
        // it when batches are ready to be processed
        isBatchProcessingPaused = true;

        // Start at 1, because 0 is reserved for the head of the list
        nextWithdrawId = 1;
        lastProcessedWithdrawId = 0;

        // Set claim window buffer to 12 hours
        claimWindowBuffer = 12 hours;
    }

    /// @inheritdoc IStakingVaultManager
    function deposit() external payable canDeposit whenNotPaused {
        uint256 amountToDeposit = msg.value.stripUnsafePrecision();

        // Mint vHYPE
        // IMPORTANT: We need to make sure that we mint the vHYPE _before_ transferring the HYPE to the staking vault,
        // otherwise the exchange rate will be incorrect. We want the exchange rate to be calculated based on the total
        // HYPE in the vault _before_ the deposit
        uint256 amountToMint = HYPETovHYPE(amountToDeposit);
        require(amountToMint > 0, ZeroAmount());
        vHYPE.mint(msg.sender, amountToMint);

        // Transfer HYPE to staking vault (HyperEVM -> HyperEVM)
        if (amountToDeposit > 0) {
            stakingVault.deposit{value: amountToDeposit}();
        }

        emit Deposit(msg.sender, amountToMint, amountToDeposit);
    }

    /// @inheritdoc IStakingVaultManager
    function queueWithdraw(uint256 vhypeAmount) external whenNotPaused returns (uint256[] memory) {
        require(vhypeAmount > 0, ZeroAmount());
        require(vHYPEtoHYPE(vhypeAmount) >= minimumWithdrawAmount, BelowMinimumWithdrawAmount());

        // This contract escrows the vHYPE until the withdraw is processed
        bool success = vHYPE.transferFrom(msg.sender, address(this), vhypeAmount);
        require(success, TransferFailed(msg.sender, vhypeAmount));

        uint256[] memory withdrawAmounts = _splitWithdraws(vhypeAmount);
        uint256[] memory withdrawIds = new uint256[](withdrawAmounts.length);
        for (uint256 i = 0; i < withdrawAmounts.length; i++) {
            uint256 withdrawId = nextWithdrawId;

            // Store the withdraw data
            Withdraw memory withdraw = Withdraw({
                id: withdrawId,
                account: msg.sender,
                vhypeAmount: withdrawAmounts[i],
                queuedAt: block.timestamp,
                batchIndex: type(uint256).max, // Not assigned to a batch yet
                cancelledAt: 0,
                claimedAt: 0
            });
            withdraws[withdrawId] = withdraw;
            accountWithdrawIds[msg.sender].push(withdrawId);

            // Add to the end of the linked list
            withdrawQueue.pushBack(withdrawId);

            // Increment the withdraw ID counter
            nextWithdrawId++;

            withdrawIds[i] = withdrawId;

            emit QueueWithdraw(msg.sender, withdrawId, withdraw);
        }

        return withdrawIds;
    }

    function _splitWithdraws(uint256 vhypeAmount) internal view returns (uint256[] memory) {
        uint256 maximumWithdrawVhypeAmount = HYPETovHYPE(maximumWithdrawAmount);

        // Calculate number of withdraws needed
        uint256 withdrawCount = (vhypeAmount + maximumWithdrawVhypeAmount - 1) / maximumWithdrawVhypeAmount;

        // Check if the last chunk would be below threshold
        uint256 lastChunkAmount = vhypeAmount % maximumWithdrawVhypeAmount;
        if (lastChunkAmount > 0 && lastChunkAmount < minimumWithdrawAmount && withdrawCount > 1) {
            withdrawCount--; // Merge last chunk into previous one
        }

        uint256[] memory withdrawAmounts = new uint256[](withdrawCount);
        uint256 remaining = vhypeAmount;

        for (uint256 i = 0; i < withdrawCount; i++) {
            if (i == withdrawCount - 1) {
                // Last withdrawal gets all remaining amount
                withdrawAmounts[i] = remaining;
            } else {
                // Take maximum for all other withdrawals
                withdrawAmounts[i] = maximumWithdrawVhypeAmount;
                remaining -= maximumWithdrawVhypeAmount;
            }
        }

        return withdrawAmounts;
    }

    /// @inheritdoc IStakingVaultManager
    function claimWithdraw(uint256 withdrawId, address destination) public whenNotPaused {
        Withdraw storage withdraw = withdraws[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(withdraw.cancelledAt == 0, WithdrawCancelled());
        require(withdraw.batchIndex != type(uint256).max, WithdrawNotProcessed());
        require(withdraw.claimedAt == 0, WithdrawClaimed());

        Batch memory batch = batches[withdraw.batchIndex];
        require(
            batch.finalizedAt > 0 && block.timestamp > batch.finalizedAt + 7 days + claimWindowBuffer,
            WithdrawUnclaimable()
        );

        uint256 withdrawExchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;
        uint256 hypeAmount = _vHYPEtoHYPE(withdraw.vhypeAmount, withdrawExchangeRate);

        // NOTE: We don't need to worry about transfer to Core timings here, because claimable HYPE is excluded
        // from the total balance (via `totalHypeProcessed`)
        stakingVault.spotSend(destination, stakingVault.HYPE_TOKEN_ID(), hypeAmount.to8Decimals());

        withdraw.claimedAt = block.timestamp;
        totalHypeClaimed += hypeAmount;

        emit ClaimWithdraw(msg.sender, withdrawId, withdraw);
    }

    /// @inheritdoc IStakingVaultManager
    function batchClaimWithdraws(uint256[] calldata withdrawIds, address destination) public whenNotPaused {
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            claimWithdraw(withdrawIds[i], destination);
        }
    }

    /// @inheritdoc IStakingVaultManager
    function cancelWithdraw(uint256 withdrawId) external whenNotPaused {
        Withdraw storage withdraw = withdraws[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(withdraw.cancelledAt == 0, WithdrawCancelled());
        require(withdraw.batchIndex == type(uint256).max, WithdrawProcessed()); // Can only cancel unprocessed withdraws

        // Remove from the linked list
        withdrawQueue.remove(withdrawId);

        // Set cancelled timestamp
        withdraw.cancelledAt = block.timestamp;

        // Refund vHYPE
        uint256 vhypeAmount = withdraw.vhypeAmount;
        bool success = vHYPE.transfer(msg.sender, vhypeAmount);
        require(success, TransferFailed(msg.sender, vhypeAmount));

        emit CancelWithdraw(msg.sender, withdrawId, withdraw);
    }

    /// @inheritdoc IStakingVaultManager
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
            if (withdraw.cancelledAt == 0) {
                batch.vhypeProcessed += withdraw.vhypeAmount;
            }

            // Update withdrawal information
            withdraw.batchIndex = currentBatchIndex;

            emit ProcessWithdraw(withdraw.account, withdraw.id, withdraw);

            // Move to next withdraw in the linked list
            lastProcessedWithdrawId = nextNodeId;
        }

        // Checkpoint the batch to storage
        _checkpointBatch(batch);

        emit ProcessBatch(currentBatchIndex, batch);
    }

    function _fetchBatch() internal view returns (Batch memory batch) {
        if (currentBatchIndex == batches.length) {
            // Initialize a new batch at the current index
            // Only enforce timing restriction if this is not the first batch
            if (lastFinalizedBatchTime != 0) {
                // There's a 1 day lockup period after HYPE is staked to a validator, so we enforce a 1 day delay between batches
                require(
                    block.timestamp > lastFinalizedBatchTime + 1 days, BatchNotReady(lastFinalizedBatchTime + 1 days)
                );

                // The documentation states that the validator stake will be unlocked after 1 day. However, the documentation
                // doesn't specify exactly when the validator stake will be unlocked, so we add an extra safety check here in
                // case it's not exactly 1 day.
                (bool exists, L1ReadLibrary.Delegation memory delegation) = stakingVault.delegation(validator);
                require(
                    exists && block.timestamp > delegation.lockedUntilTimestamp / 1000, /* convert to seconds for comparison */
                    BatchNotReady(delegation.lockedUntilTimestamp / 1000 /* convert to seconds */ )
                );
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

    /// @dev Stores the batch, either by appending a new one or by overwriting the current batch.
    function _checkpointBatch(Batch memory batch) internal {
        if (currentBatchIndex == batches.length) {
            batches.push(batch);
        } else {
            batches[currentBatchIndex] = batch;
        }
    }

    /// @inheritdoc IStakingVaultManager
    function finalizeBatch() external whenNotPaused whenBatchProcessingNotPaused {
        // Check if we have a batch to finalize
        require(currentBatchIndex < batches.length, NothingToFinalize());

        Batch memory batch = batches[currentBatchIndex];

        // Check if we can finalize the batch. This will revert if we cannot finalize the batch.
        _canFinalizeBatch(batch);

        uint256 depositsInBatch = stakingVault.evmBalance();
        uint256 withdrawsInBatch = _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);

        // Update totalHypeProcessed to track reserved HYPE for withdrawals
        totalHypeProcessed += withdrawsInBatch;

        // Save the timestamp that the batch was finalized
        batches[currentBatchIndex].finalizedAt = block.timestamp;
        lastFinalizedBatchTime = block.timestamp;

        // Burn the escrowed vHYPE (burn from this contract's balance)
        vHYPE.burn(batch.vhypeProcessed);

        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        L1ReadLibrary.SpotBalance memory spotBalance = stakingVault.spotBalance(stakingVault.HYPE_TOKEN_ID());

        uint256 expectedSpotBalance = spotBalance.total.to18Decimals() + depositsInBatch;
        uint256 pendingWithdrawals = delegatorSummary.totalPendingWithdrawal.to18Decimals();
        uint256 expectedAvailableForWithdraws = expectedSpotBalance + pendingWithdrawals;
        uint256 neededForWithdraws = totalHypeProcessed - totalHypeClaimed;

        // Always transfer the full deposit amount to HyperCore spot
        if (depositsInBatch > 0) {
            stakingVault.transferHypeToCore(depositsInBatch);
        }

        // Net out the deposits and withdraws
        if (expectedAvailableForWithdraws > neededForWithdraws) {
            // If we have more HYPE than needed
            uint256 totalExcess = expectedAvailableForWithdraws - neededForWithdraws;

            // We can only stake the excess if it's in spot. If there's excess in
            // pending withdrawals, we can't re-stake it. Once it lands in spot,
            // the next finalizeBatch will stake it.
            uint256 amountToStake = Math.min(totalExcess, expectedSpotBalance);
            stakingVault.stake(validator, amountToStake.to8Decimals());
        } else if (expectedAvailableForWithdraws < neededForWithdraws) {
            // If we don't have enough HYPE to cover all expected withdraws, we need to
            // withdraw some HYPE from the staking vault
            uint256 amountToUnstake = neededForWithdraws - expectedAvailableForWithdraws;
            stakingVault.unstake(validator, amountToUnstake.to8Decimals());
        }

        emit FinalizeBatch(currentBatchIndex, batches[currentBatchIndex]);

        // Increment the batch index
        currentBatchIndex++;
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

    /// @inheritdoc IStakingVaultManager
    function getBatch(uint256 index) external view returns (Batch memory) {
        return batches[index];
    }

    /// @inheritdoc IStakingVaultManager
    function getBatchesLength() external view returns (uint256) {
        return batches.length;
    }

    /// @inheritdoc IStakingVaultManager
    function getWithdraw(uint256 withdrawId) external view returns (Withdraw memory) {
        return withdraws[withdrawId];
    }

    /// @inheritdoc IStakingVaultManager
    function getWithdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.sizeOf();
    }

    /// @inheritdoc IStakingVaultManager
    function getWithdrawAmount(uint256 withdrawId) external view returns (uint256) {
        Withdraw memory withdraw = withdraws[withdrawId];
        uint256 vhypeAmount = withdraw.vhypeAmount;

        // If the withdraw hasn't been processed yet, use the current exchange rate
        if (withdraw.batchIndex == type(uint256).max) {
            return vHYPEtoHYPE(vhypeAmount);
        }

        // Otherwise, use the exchange rate from the batch
        Batch memory batch = batches[withdraw.batchIndex];
        uint256 _exchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;
        return _vHYPEtoHYPE(vhypeAmount, _exchangeRate);
    }

    /// @inheritdoc IStakingVaultManager
    function getWithdrawClaimableAt(uint256 withdrawId) external view returns (uint256) {
        Withdraw memory withdraw = withdraws[withdrawId];
        uint256 batchIndex = withdraw.batchIndex;
        // Not assigned to a batch yet, return max uint256
        if (batchIndex == type(uint256).max) {
            return type(uint256).max;
        }
        Batch memory batch = batches[batchIndex];
        // Batch not finalized yet, return max uint256
        if (batch.finalizedAt == 0) {
            return type(uint256).max;
        }
        return batch.finalizedAt + 7 days + claimWindowBuffer;
    }

    /// @inheritdoc IStakingVaultManager
    function HYPETovHYPE(uint256 hypeAmount) public view returns (uint256) {
        return _HYPETovHYPE(hypeAmount, exchangeRate());
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function _HYPETovHYPE(uint256 hypeAmount, uint256 _exchangeRate) internal pure returns (uint256) {
        if (_exchangeRate == 0) {
            return 0;
        }
        return Math.mulDiv(hypeAmount, 1e18, _exchangeRate);
    }

    /// @inheritdoc IStakingVaultManager
    function vHYPEtoHYPE(uint256 vHYPEAmount) public view returns (uint256) {
        return _vHYPEtoHYPE(vHYPEAmount, exchangeRate());
    }

    /// forge-lint: disable-next-line(mixed-case-function, mixed-case-variable)
    function _vHYPEtoHYPE(uint256 vHYPEAmount, uint256 _exchangeRate) internal pure returns (uint256) {
        if (_exchangeRate == 0) {
            return 0;
        }
        return Math.mulDiv(vHYPEAmount, _exchangeRate, 1e18);
    }

    /// @inheritdoc IStakingVaultManager
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

    /// @inheritdoc IStakingVaultManager
    function totalBalance() public view returns (uint256) {
        // EVM + Spot + Staking account balances
        uint256 accountBalances = stakingAccountBalance() + spotAccountBalance() + stakingVault.evmBalance();

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
        L1ReadLibrary.SpotBalance memory spotBalance = stakingVault.spotBalance(stakingVault.HYPE_TOKEN_ID());
        return spotBalance.total.to18Decimals();
    }

    /// @inheritdoc IStakingVaultManager
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

    /// @inheritdoc IStakingVaultManager
    function setMinimumStakeBalance(uint256 _minimumStakeBalance) public onlyOwner {
        // If we're in the middle of processing a batch, check that we haven't processed more HYPE
        // than what we'd have left after setting the minimum stake balance
        if (currentBatchIndex < batches.length) {
            uint256 newWithdrawCapacity = totalBalance() - _minimumStakeBalance;
            StakingVaultManager.Batch memory batch = batches[currentBatchIndex];
            uint256 _exchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;
            require(
                newWithdrawCapacity >= _vHYPEtoHYPE(batch.vhypeProcessed, _exchangeRate), MinimumStakeBalanceTooLarge()
            );
        }
        minimumStakeBalance = _minimumStakeBalance;
    }

    /// @notice Switches the validator to delegate HYPE to
    /// @param newValidator The new validator
    function switchValidator(address newValidator) external onlyOwner {
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        if (delegatorSummary.delegated > 0) {
            stakingVault.tokenRedelegate(validator, newValidator, delegatorSummary.delegated);
        }

        validator = newValidator;
    }

    /// @notice Sets the minimum deposit amount (in 18 decimals)
    /// @param _minimumDepositAmount The minimum deposit amount (in 18 decimals)
    function setMinimumDepositAmount(uint256 _minimumDepositAmount) external onlyOwner {
        minimumDepositAmount = _minimumDepositAmount;
    }

    /// @notice Sets the minimum withdraw amount (in 18 decimals)
    /// @param _minimumWithdrawAmount The minimum withdraw amount (in 18 decimals)
    function setMinimumWithdrawAmount(uint256 _minimumWithdrawAmount) external onlyOwner {
        minimumWithdrawAmount = _minimumWithdrawAmount;
    }

    /// @notice Sets the maximum withdraw amount (in 18 decimals)
    /// @param _maximumWithdrawAmount The maximum withdraw amount (in 18 decimals)
    function setMaximumWithdrawAmount(uint256 _maximumWithdrawAmount) external onlyOwner {
        maximumWithdrawAmount = _maximumWithdrawAmount;
    }

    /// @notice Sets the claim window buffer (in seconds)
    /// @param _claimWindowBuffer The claim window buffer (in seconds)
    function setClaimWindowBuffer(uint256 _claimWindowBuffer) external onlyOwner {
        claimWindowBuffer = _claimWindowBuffer;
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
            } else {
                break;
            }
        }

        emit ResetBatch(currentBatchIndex, batch);
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

        emit FinalizeResetBatch(currentBatchIndex, batch);
    }

    /// @notice Applies a slash to a batch
    /// @param batchIndex The index of the batch to apply the slash to
    /// @param slashedExchangeRate The new exchange rate that should be applied to the batch (in 18 decimals)
    function applySlash(uint256 batchIndex, uint256 slashedExchangeRate) external onlyOwner {
        require(batchIndex < batches.length, InvalidBatch(batchIndex));
        Batch storage batch = batches[batchIndex];

        // Only allow slashing batches that are within the slash window
        require(
            block.timestamp <= batch.finalizedAt + 7 days + claimWindowBuffer,
            CannotSlashBatchOutsideSlashWindow(batchIndex)
        );

        // Only allow slashing batches that have been finalized. If there's currently a batch processing, and
        // that batch has an incorrect snapshot exchange rate, we should first call resetBatch and finalizeResetBatch.
        // This will reset the withdrawals in the current batch, and remove the batch from the array. Then we can
        // call processBatch to use the live, slashed exchange rate.
        require(batch.finalizedAt > 0, InvalidBatch(batchIndex));

        uint256 oldExchangeRate = batch.slashed ? batch.slashedExchangeRate : batch.snapshotExchangeRate;

        // Only adjust totalHypeProcessed if the batch has been finalized
        if (batch.finalizedAt > 0) {
            totalHypeProcessed -= _vHYPEtoHYPE(batch.vhypeProcessed, oldExchangeRate);
            totalHypeProcessed += _vHYPEtoHYPE(batch.vhypeProcessed, slashedExchangeRate);
        }

        batch.slashedExchangeRate = slashedExchangeRate;
        batch.slashed = true;

        emit ApplySlash(batchIndex, slashedExchangeRate);
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

    /// @inheritdoc IStakingVaultManager
    function windDown() external onlyOwner {
        setMinimumStakeBalance(0);
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
