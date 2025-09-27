// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base} from "./Base.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";

contract StakingVaultManager is Base {
    using Converters for *;

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

    /// @notice Thrown if the from and to validators are the same.
    error RedelegateToSameValidator();

    /// @notice Thrown if the validator is locked until a timestamp in the future.
    error StakeLockedUntilTimestamp(address validator, uint64 lockedUntilTimestamp);

    /// @notice Emitted when HYPE is deposited into the vault
    /// @param depositor The address that deposited the HYPE
    /// @param minted The amount of vHYPE minted (in 18 decimals)
    /// @param deposited The amount of HYPE deposited (in 18 decimals)
    event Deposit(address indexed depositor, uint256 minted, uint256 deposited);

    /// @notice Emitted when an HYPE stake is moved from one validator to another
    /// @param fromValidator The validator from which the HYPE stake is being moved
    /// @param toValidator The validator to which the HYPE stake is being moved
    /// @param amount The amount of HYPE being moved (in 18 decimals)
    event RedelegateStake(address indexed fromValidator, address indexed toValidator, uint256 amount);

    /// @notice Emitted when an emergency staking withdraw is executed
    /// @param sender The address that executed the emergency withdraw
    /// @param amount The amount of HYPE withdrawn
    /// @param purpose The purpose of the withdrawal
    event EmergencyStakingWithdraw(address indexed sender, uint256 amount, string purpose);

    /// @dev A batch of withdraws that are processed together
    struct Batch {
        /// @dev The total amount of withdraws processed in this batch (vHYPE; in 18 decimals)
        uint256 vhypeProcessed;
        /// @dev The timestamp when the batch was processed
        uint256 processedAt;
        /// @dev The exchange rate at the time the batch was processed (in 18 decimals)
        uint256 snapshotExchangeRate;
        /// @dev The exchange rate if a slash was applied to the batch (in 18 decimals)
        uint256 slashedExchangeRate;
        /// @dev Whether the batch was slashed
        bool slashed;
    }

    /// @dev A withdraw from the vault
    struct Withdraw {
        /// @dev The account that requested the withdraw
        address account;
        /// @dev The amount of vHYPE to redeem (in 18 decimals)
        /// @dev A 0 amount indicates that the withdraw was cancelled
        uint256 vhypeAmount;
        /// @dev The index of the batch this withdraw was assigned to
        /// @dev If the withdraw has not been assigned to a batch, this is set to type(uint256).max
        uint256 batchIndex;
        /// @dev Whether the withdraw has been claimed
        bool claimed;
    }

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// forge-lint: disable-next-line(mixed-case-variable)
    VHYPE public vHYPE;

    IStakingVault public stakingVault;

    /// @dev The default validator to delegate HYPE to
    address public defaultValidator;

    /// @dev The minimum amount of HYPE that needs to remain staked in the vault (in 18 decimals)
    uint256 public minimumStakeBalance;

    /// @dev The minimum amount of HYPE that can be deposited (in 18 decimals)
    uint256 public minimumDepositAmount;

    /// @dev Whether batch processing is paused
    bool public isBatchProcessingPaused;

    /// @dev Batches of deposits and withdraws
    Batch[] private batches;

    /// @dev The current batch index
    uint256 public currentBatchIndex;

    /// @dev The withdraw queue (append-only)
    Withdraw[] private withdrawQueue;

    /// @dev The next withdraw index
    uint256 public nextWithdrawIndex;

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
        address _defaultValidator,
        uint256 _minimumStakeBalance,
        uint256 _minimumDepositAmount
    ) public initializer {
        __Base_init(_roleRegistry);

        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        defaultValidator = _defaultValidator;
        minimumStakeBalance = _minimumStakeBalance;
        minimumDepositAmount = _minimumDepositAmount;

        // Set batch processing to paused by default. OWNER will enable
        // it when batches are ready to be processed
        isBatchProcessingPaused = true;
    }

    /// @notice Deposits HYPE into the vault, and mints the equivalent amount of vHYPE. Refunds any excess HYPE if only a partial deposit is made. Reverts if the vault is full.
    function deposit() public payable canDeposit whenNotPaused {
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
    function queueWithdraw(uint256 vhypeAmount) public whenNotPaused returns (uint256) {
        require(vhypeAmount > 0, ZeroAmount());

        // This contract escrows the vHYPE until the withdraw is processed
        bool success = vHYPE.transferFrom(msg.sender, address(this), vhypeAmount);
        require(success, TransferFailed(msg.sender, vhypeAmount));

        Withdraw memory withdraw = Withdraw({
            account: msg.sender,
            vhypeAmount: vhypeAmount,
            batchIndex: type(uint256).max, // Not assigned to a batch yet
            claimed: false
        });
        withdrawQueue.push(withdraw);

        // ID of the withdraw is the index of the withdraw in the queue
        return withdrawQueue.length - 1;
    }

    /// @notice Claims a withdraw
    /// @param withdrawId The ID of the withdraw to claim
    /// @param destination The address to send the HYPE to
    function claimWithdraw(uint256 withdrawId, address destination) public whenNotPaused {
        Withdraw storage withdraw = withdrawQueue[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(withdraw.vhypeAmount > 0, WithdrawCancelled());
        require(withdraw.claimed == false, WithdrawClaimed());

        Batch memory batch = batches[withdraw.batchIndex];
        require(block.timestamp > batch.processedAt + 7 days, WithdrawUnclaimable()); // TODO: Should we add a buffer?

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
        require(spotBalance.total >= hypeAmount, InsufficientBalance());

        stakingVault.spotSend(destination, HYPE_TOKEN_ID, hypeAmount.to8Decimals());

        withdraw.claimed = true;
    }

    /// @notice Cancels a withdraw. A withdraw can only be cancelled if it has not been processed yet.
    /// @param withdrawId The ID of the withdraw to cancel
    function cancelWithdraw(uint256 withdrawId) public whenNotPaused {
        Withdraw storage withdraw = withdrawQueue[withdrawId];
        require(msg.sender == withdraw.account, NotAuthorized());
        require(withdraw.vhypeAmount > 0, WithdrawCancelled());
        require(withdrawId >= nextWithdrawIndex, WithdrawProcessed());

        // Refund vHYPE
        bool success = vHYPE.transfer(msg.sender, withdraw.vhypeAmount);
        require(success, TransferFailed(msg.sender, withdraw.vhypeAmount));

        // Set to 0 to indicate that the withdraw was cancelled
        withdraw.vhypeAmount = 0;
    }

    /// @notice Processes the current batch of withdraws
    /// @dev Safe to be called by anyone, as it will only process the batch if it's ready to be processed
    function processCurrentBatch() public whenNotPaused whenBatchProcessingNotPaused {
        // Check if it's been at least one day since the last batch was processed
        if (currentBatchIndex > 0) {
            uint256 previousBatchIndex = currentBatchIndex - 1;
            require(
                block.timestamp > batches[previousBatchIndex].processedAt + 1 days, // TODO: Should we add a buffer?
                BatchNotReady(batches[previousBatchIndex].processedAt + 1 days)
            );
        }

        uint256 snapshotExchangeRate = exchangeRate();
        uint256 withdrawCapacityAvailable = totalBalance() - minimumStakeBalance;

        Batch memory batch = Batch({
            vhypeProcessed: 0,
            processedAt: block.timestamp,
            snapshotExchangeRate: snapshotExchangeRate,
            slashedExchangeRate: 0,
            slashed: false
        });

        // Process withdraws from the queue until we run out of capacity, or until we run out of withdraws
        if (withdrawQueue.length > 0) {
            while (withdrawCapacityAvailable > 0 && nextWithdrawIndex < withdrawQueue.length) {
                Withdraw storage withdraw = withdrawQueue[nextWithdrawIndex];
                uint256 expectedHypeAmount = _vHYPEtoHYPE(withdraw.vhypeAmount, snapshotExchangeRate);
                if (expectedHypeAmount > withdrawCapacityAvailable) {
                    break;
                }

                // Burn the escrowed vHYPE
                vHYPE.burn(withdraw.vhypeAmount);

                batch.vhypeProcessed += withdraw.vhypeAmount;
                withdraw.batchIndex = currentBatchIndex;
                totalHypeProcessed += expectedHypeAmount;
                withdrawCapacityAvailable -= expectedHypeAmount;
                nextWithdrawIndex++;
            }
        }

        batches.push(batch);
        currentBatchIndex++;

        _finalizeBatch(batch);
    }

    function _finalizeBatch(Batch memory batch) internal {
        uint256 depositsInBatch = address(stakingVault).balance;
        uint256 withdrawsInBatch = _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);

        if (depositsInBatch > 0) {
            // Transfer all deposited HYPE to HyperCore spot account
            stakingVault.transferHypeToCore(depositsInBatch);
        }

        // Net out the deposits and withdraws in the batch
        if (depositsInBatch > withdrawsInBatch) {
            // All withdraws are covered by deposits

            // Stake the excess HYPE
            uint256 amountToStake = depositsInBatch - withdrawsInBatch;
            stakingVault.stakingDeposit(amountToStake.to8Decimals());
            stakingVault.tokenDelegate(defaultValidator, amountToStake.to8Decimals());
        } else if (depositsInBatch < withdrawsInBatch) {
            // Not enough deposits to cover all withdraws; we need to withdraw some HYPE from the staking vault

            // Withdraw the amount not covered by deposits from the staking vault
            uint256 amountToWithdraw = withdrawsInBatch - depositsInBatch;
            stakingVault.tokenUndelegate(defaultValidator, amountToWithdraw.to8Decimals());
            stakingVault.stakingWithdraw(amountToWithdraw.to8Decimals());
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

    /// @notice Returns the withdraw at the given index
    /// @param index The index of the withdraw to return
    function getWithdraw(uint256 index) public view returns (Withdraw memory) {
        return withdrawQueue[index];
    }

    /// @notice Returns the length of the withdraw queue
    function getWithdrawQueueLength() public view returns (uint256) {
        return withdrawQueue.length;
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
        // The total amount of HYPE that is reserved to be returned to users for withdraws, but is still in
        // under the StakingVault accounts because they have not finished processing or been claimed
        uint256 reservedHypeForWithdraws = totalHypeProcessed - totalHypeClaimed;

        return stakingAccountBalance() + spotAccountBalance() + address(stakingVault).balance - reservedHypeForWithdraws;
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Owner Actions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the minimum stake balance (in 18 decimals)
    /// @dev Minimum stake balance is the total amount of HYPE that must remain staked in the vault
    function setMinimumStakeBalance(uint256 _minimumStakeBalance) public onlyOwner {
        minimumStakeBalance = _minimumStakeBalance;
    }

    /// @notice Sets the default validator to delegate HYPE to
    /// @param _defaultValidator The default validator to delegate HYPE to
    function setDefaultValidator(address _defaultValidator) public onlyOwner {
        defaultValidator = _defaultValidator;
    }

    /// @notice Sets the minimum deposit amount (in 18 decimals)
    /// @param _minimumDepositAmount The minimum deposit amount (in 18 decimals)
    function setMinimumDepositAmount(uint256 _minimumDepositAmount) public onlyOwner {
        minimumDepositAmount = _minimumDepositAmount;
    }

    /// @notice Sets whether batch processing is paused
    /// @param _isBatchProcessingPaused Whether batch processing is paused
    function setBatchProcessingPaused(bool _isBatchProcessingPaused) public onlyOwner {
        isBatchProcessingPaused = _isBatchProcessingPaused;
    }

    /// @notice Applies a slash to a batch
    /// @param batchIndex The index of the batch to apply the slash to
    /// @param slashedExchangeRate The new exchange rate that should be applied to the batch (in 18 decimals)
    function applySlash(uint256 batchIndex, uint256 slashedExchangeRate) public onlyOwner {
        require(batchIndex < batches.length, InvalidBatch(batchIndex));
        Batch storage batch = batches[batchIndex];
        batch.slashedExchangeRate = slashedExchangeRate;
        batch.slashed = true;

        totalHypeProcessed -= _vHYPEtoHYPE(batch.vhypeProcessed, batch.snapshotExchangeRate);
        totalHypeProcessed += _vHYPEtoHYPE(batch.vhypeProcessed, batch.slashedExchangeRate);
    }

    /// @notice Moves an HYPE stake from one validator to another
    /// @param fromValidator The validator from which the HYPE stake is being moved
    /// @param toValidator The validator to which the HYPE stake is being moved
    /// @param amount The amount of HYPE being moved (in 18 decimals)
    function redelegateStake(address fromValidator, address toValidator, uint256 amount)
        external
        onlyOwner
        canUndelegateStake(fromValidator, amount)
    {
        require(fromValidator != toValidator, RedelegateToSameValidator());

        stakingVault.tokenUndelegate(fromValidator, amount.to8Decimals());
        stakingVault.tokenDelegate(toValidator, amount.to8Decimals());
        emit RedelegateStake(fromValidator, toValidator, amount);
    }

    /// @notice Execute an emergency staking withdraw
    /// @dev Immediately undelegates HYPE and initiates a staking withdraw
    /// @dev Amount will be available in the StakingVault's spot account balance after 7 days.
    /// @param validator The validator from which the HYPE stake is being moved
    /// @param amount Amount to withdraw (in 18 decimals)
    /// @param purpose Description of withdrawal purpose
    function emergencyStakingWithdraw(address validator, uint256 amount, string calldata purpose)
        external
        onlyOwner
        canUndelegateStake(validator, amount)
    {
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        require(delegatorSummary.delegated >= amount.to8Decimals(), InsufficientBalance());

        // Immediately undelegate HYPE
        stakingVault.tokenUndelegate(validator, amount.to8Decimals());

        // Queue a staking withdrawal, subject to the 7-day withdrawal queue. Amount will be available in
        // the StakingVault's spot account balance after 7 days.
        stakingVault.stakingWithdraw(amount.to8Decimals());
        emit EmergencyStakingWithdraw(msg.sender, amount, purpose);
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

    modifier canUndelegateStake(address validator, uint256 amount) {
        _canUndelegateStake(validator, amount);
        _;
    }

    function _canUndelegateStake(address validator, uint256 amount) internal view {
        require(amount > 0, ZeroAmount());

        L1ReadLibrary.Delegation[] memory delegations = stakingVault.delegations();
        uint64 delegatedAmount = 0;
        uint64 lockedUntilTimestamp = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].validator == validator) {
                delegatedAmount = delegations[i].amount;
                lockedUntilTimestamp = delegations[i].lockedUntilTimestamp;
                break;
            }
        }
        require(delegatedAmount >= amount.to8Decimals(), InsufficientBalance());
        require(lockedUntilTimestamp <= block.timestamp, StakeLockedUntilTimestamp(validator, lockedUntilTimestamp));
    }
}
