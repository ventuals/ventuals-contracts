// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Base} from "./Base.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";

contract GenesisVaultManager is Base {
    using Converters for *;

    /// @notice Thrown if HYPE transfer fails to given recipient for specified amount.
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Thrown if an amount of 0 is provided.
    error ZeroAmount();

    /// @notice Thrown if an amount exceeds the balance.
    error InsufficientBalance();

    /// @notice Thrown if the vault is full.
    error VaultFull();

    /// @notice Thrown if the deposit amount is below the minimum deposit amount.
    error BelowMinimumDepositAmount();

    /// @notice Thrown if the deposit limit is reached.
    error DepositLimitReached();

    /// @notice Thrown if the from and to validators are the same.
    error RedelegateToSameValidator();

    /// @notice Thrown if the validator is locked until a timestamp in the future.
    error StakeLockedUntilTimestamp(address validator, uint64 lockedUntilTimestamp);

    /// @notice Emitted when HYPE is deposited into the vault
    /// @param depositor The address that deposited the HYPE
    /// @param minted The amount of vHYPE minted (in 18 decimals)
    /// @param deposited The amount of HYPE deposited (in 18 decimals)
    /// @param refunded The amount of HYPE refunded (in 18 decimals)
    event Deposit(address indexed depositor, uint256 minted, uint256 deposited, uint256 refunded);

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

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// forge-lint: disable-next-line(mixed-case-variable)
    VHYPE public vHYPE;

    IStakingVault public stakingVault;

    /// @notice The total HYPE capacity of the vault (in 18 decimals)
    /// @dev This is the total amount of HYPE that can be deposited into the vault.
    /// @dev All HYPE will be moved to the vault's staking account and staked with validators (on HyperCore).
    uint256 public vaultCapacity;

    /// @dev The default validator to delegate HYPE to
    address public defaultValidator;

    /// @dev The minimum amount of HYPE that can be deposited (in 18 decimals)
    uint256 public minimumDepositAmount;

    /// @dev The default maximum amount of HYPE that can be deposited for each address (in 18 decimals)
    uint256 public defaultDepositLimit;

    /// @dev A whitelist of addresses that have different deposit limits
    /// @dev Addresses may have higher or lower deposit limits than the default. Set the whitelist
    ///      deposit limit to 0 to disable the whitelist for that address.
    mapping(address => uint256) public whitelistDepositLimits;

    /// @dev The cumulative amount of HYPE deposited by each address
    mapping(address => uint256) public depositsByAddress;

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
        uint256 _vaultCapacity,
        address _defaultValidator,
        uint256 _defaultDepositLimit,
        uint256 _minimumDepositAmount
    ) public initializer {
        __Base_init(_roleRegistry);

        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        vaultCapacity = _vaultCapacity;
        defaultValidator = _defaultValidator;
        defaultDepositLimit = _defaultDepositLimit;
        minimumDepositAmount = _minimumDepositAmount;
    }

    /// @notice Deposits HYPE into the vault, and mints the equivalent amount of vHYPE. Refunds any excess HYPE if only a partial deposit is made. Reverts if the vault is full.
    function deposit() public payable canDeposit whenNotPaused {
        uint256 requestedDepositAmount = msg.value;
        uint256 availableCapacity = Math.min(vaultCapacity - totalBalance(), remainingDepositLimit(msg.sender));
        uint256 amountToDeposit = Math.min(requestedDepositAmount, availableCapacity);

        // Update cumulative deposits for this address
        depositsByAddress[msg.sender] += amountToDeposit;

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

        // Refund any excess HYPE
        uint256 amountToRefund = requestedDepositAmount - amountToDeposit;
        if (amountToRefund > 0) {
            (bool success,) = payable(msg.sender).call{value: amountToRefund}("");
            require(success, TransferFailed(msg.sender, amountToRefund));
        }

        emit Deposit(
            msg.sender, /* depositor */
            amountToMint, /* minted */
            amountToDeposit, /* deposited */
            amountToRefund /* refunded */
        );
    }

    /// @notice Calculates the vHYPE amount for a given HYPE amount, based on the exchange rate
    /// @param hypeAmount The HYPE amount to convert (in 18 decimals)
    /// @return The vHYPE amount (in 18 decimals)
    /// forge-lint: disable-next-line(mixed-case-function)
    function HYPETovHYPE(uint256 hypeAmount) public view returns (uint256) {
        uint256 _exchangeRate = exchangeRate();
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
        uint256 _exchangeRate = exchangeRate();
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

    /// @notice Returns the total HYPE balance in the vault (in 18 decimals)
    /// @dev Sum of staking account balance (on HyperCore), spot account balance (on HyperCore), contract balance (on HyperEVM)
    function totalBalance() public view returns (uint256) {
        return stakingAccountBalance() + spotAccountBalance() + address(stakingVault).balance;
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

    /// @notice Returns the remaining deposit limit for an address (in 18 decimals)
    /// @param depositor The address to check the remaining deposit limit for
    /// @return The remaining deposit limit (in 18 decimals)
    function remainingDepositLimit(address depositor) public view returns (uint256) {
        uint256 depositLimit = whitelistDepositLimits[depositor];
        if (depositLimit == 0) {
            depositLimit = defaultDepositLimit;
        }

        // IMPORTANT: We need to prevent possible underflow here. This may happen if we lower the default
        // deposit limit after a user has already deposited more than the new limit.
        //
        // Example:
        // - Default deposit limit is 100 HYPE
        // - User deposits 150 HYPE
        // - We lower the default deposit limit to 50 HYPE
        // - remainingDepositLimit() should return 0, not underflow
        (bool success, uint256 remaining) = Math.trySub(depositLimit, depositsByAddress[depositor]);
        if (!success) {
            return 0;
        }
        return remaining;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Operator Actions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Transfers all HYPE from the vault's HyperEVM balance to HyperCore and delegates it
    /// @dev This function can only be called by the operator
    function transferToCoreAndDelegate() public onlyOperator {
        uint256 amount = address(stakingVault).balance;
        _transferToCoreAndDelegate(amount);
    }

    /// @notice Transfers HYPE from the vault's HyperEVM balance to HyperCore and delegates it
    /// @dev This function can only be called by the operator
    /// @param amount The amount of HYPE to transfer (in 18 decimals)
    function transferToCoreAndDelegate(uint256 amount) public onlyOperator {
        _transferToCoreAndDelegate(amount);
    }

    /// @notice Transfers HYPE from the vault's HyperEVM balance to HyperCore and delegates it
    /// @param amount The amount of HYPE to transfer (in 18 decimals)
    function _transferToCoreAndDelegate(uint256 amount) internal {
        require(amount > 0, ZeroAmount());
        require(amount <= address(stakingVault).balance, InsufficientBalance());

        stakingVault.transferHypeToCore(amount); // HyperEVM -> HyperCore spot
        stakingVault.stakingDeposit(amount.to8Decimals()); // HyperCore spot -> HyperCore staking
        stakingVault.tokenDelegate(defaultValidator, amount.to8Decimals(), false); // Delegate HYPE to validator (from HyperCore staking)
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       Owner Actions                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the vault capacity (in 18 decimals)
    /// @dev Vault capacity is the total amount of HYPE that can be deposited into the staking vault
    function setVaultCapacity(uint256 _vaultCapacity) public onlyOwner {
        vaultCapacity = _vaultCapacity;
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

    /// @notice Sets the default deposit limit per address (in 18 decimals)
    /// @param _defaultDepositLimit The default deposit limit per address (in 18 decimals)
    function setDefaultDepositLimit(uint256 _defaultDepositLimit) public onlyOwner {
        defaultDepositLimit = _defaultDepositLimit;
    }

    /// @notice Whitelists a deposit limit for an address (in 18 decimals)
    /// @param depositor The address to whitelist a custom deposit limit for
    /// @param limit The deposit limit (in 18 decimals)
    function setWhitelistDepositLimit(address depositor, uint256 limit) public onlyOwner {
        whitelistDepositLimits[depositor] = limit;
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

        stakingVault.tokenDelegate(fromValidator, amount.to8Decimals(), true);
        stakingVault.tokenDelegate(toValidator, amount.to8Decimals(), false);
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
        stakingVault.tokenDelegate(validator, amount.to8Decimals(), true);

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
        require(totalBalance() < vaultCapacity, VaultFull());
        uint256 remainingCapacity = vaultCapacity - totalBalance();
        require(
            // The deposit amount should be at least the minimum deposit amount, unless the remaining capacity is less than the minimum deposit amount
            msg.value >= minimumDepositAmount
                || (msg.value >= remainingCapacity && remainingCapacity < minimumDepositAmount),
            BelowMinimumDepositAmount()
        );
        require(remainingDepositLimit(msg.sender) > 0, DepositLimitReached());
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
