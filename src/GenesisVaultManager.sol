// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {RoleRegistry} from "./RoleRegistry.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";

contract GenesisVaultManager is Initializable, UUPSUpgradeable {
    using Converters for *;

    RoleRegistry public roleRegistry;
    VHYPE public vHYPE;
    IStakingVault public stakingVault;

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// @notice The total HYPE capacity of the vault (in 18 decimals)
    /// @dev This is the total amount of HYPE that can be deposited into the vault.
    /// @dev All HYPE will be moved to the vault's staking account and staked with validators (on HyperCore).
    uint256 public vaultCapacity;

    /// @dev The default validator to delegate HYPE to
    address public defaultValidator;

    /// @dev The default maximum amount of HYPE that can be deposited for each address (in 18 decimals)
    uint256 public defaultDepositLimit;

    /// @dev A whitelist of addresses that have higher deposit limits
    mapping(address => uint256) public whitelistDepositLimits;

    /// @dev The cumulative amount of HYPE deposited by each address
    mapping(address => uint256) public depositsByAddress;

    uint256 public lastHyperCoreTransferBlockNumber;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint64 _hypeTokenId) {
        HYPE_TOKEN_ID = _hypeTokenId;

        _disableInitializers();
    }

    function initialize(
        address _roleRegistry,
        address _vHYPE,
        address _stakingVault,
        uint256 _vaultCapacity,
        address _defaultValidator,
        uint256 _defaultDepositLimit
    ) public initializer {
        __UUPSUpgradeable_init();

        roleRegistry = RoleRegistry(_roleRegistry);
        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        vaultCapacity = _vaultCapacity;
        defaultValidator = _defaultValidator;
        defaultDepositLimit = _defaultDepositLimit;
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
            (bool success,) = payable(address(stakingVault)).call{value: amountToDeposit}("");
            require(success, "Transfer failed"); // TODO: Change to typed error
        }

        // Refund any excess HYPE
        if (requestedDepositAmount > amountToDeposit) {
            (bool success,) = payable(msg.sender).call{value: requestedDepositAmount - amountToDeposit}("");
            require(success, "Refund failed"); // TODO: Change to typed error
        }

        emit Deposit(
            msg.sender, /* depositor */
            amountToMint, /* minted */
            amountToDeposit, /* deposited */
            requestedDepositAmount - amountToDeposit /* refunded */
        );
    }

    /// @notice Calculates the vHYPE amount for a given HYPE amount, based on the exchange rate
    /// @param hypeAmount The HYPE amount to convert (in 18 decimals)
    /// @return The vHYPE amount (in 18 decimals)
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

    /// @notice Transfers all HYPE from the vault's HyperEVM balance to HyperCore and delegates it
    /// @dev This function is called by the operator
    function transferToHyperCoreAndDelegate() public onlyOperator {
        uint256 amount = address(stakingVault).balance;
        transferToHyperCoreAndDelegate(amount);
    }

    /// @notice Transfers HYPE from the vault's HyperEVM balance to HyperCore and delegates it
    /// @dev This function is called by the operator
    /// @param amount The amount of HYPE to transfer (in 18 decimals)
    function transferToHyperCoreAndDelegate(uint256 amount) public onlyOperator {
        require(
            block.number >= lastHyperCoreTransferBlockNumber + 1, "Cannot transfer to HyperCore until the next block"
        ); // TODO: Change to typed error
        require(amount > 0, "Amount must be greater than 0"); // TODO: Change to typed error
        stakingVault.transferHypeToCore(amount); // HyperEVM -> HyperCore spot
        stakingVault.stakingDeposit(amount.to8Decimals()); // HyperCore spot -> HyperCore staking
        stakingVault.tokenDelegate(defaultValidator, amount.to8Decimals(), false); // Delegate HYPE to validator (from HyperCore staking)

        lastHyperCoreTransferBlockNumber = block.number;
    }

    /// @notice Moves an HYPE stake from one validator to another
    /// @param fromValidator The validator from which the HYPE stake is being moved
    /// @param toValidator The validator to which the HYPE stake is being moved
    /// @param amount The amount of HYPE being moved (in 18 decimals)
    function redelegateStake(address fromValidator, address toValidator, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0"); // TODO: Change to typed error
        require(fromValidator != toValidator, "From and to validators cannot be the same"); // TODO: Change to typed error

        stakingVault.tokenDelegate(fromValidator, amount.to8Decimals(), true);
        stakingVault.tokenDelegate(toValidator, amount.to8Decimals(), false);
        emit RedelegateStake(fromValidator, toValidator, amount);
    }

    /// @notice Execute an emergency staking withdraw
    /// @dev Immediately undelegates HYPE and initiates a staking withdraw
    /// @dev Amount will be available in the StakingVault's spot account balance after 7 days.
    /// @param amount Amount to withdraw (in 18 decimals)
    /// @param purpose Description of withdrawal purpose
    function emergencyStakingWithdraw(uint256 amount, string calldata purpose) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0"); // TODO: Change to typed error
        require(bytes(purpose).length > 0, "Purpose must be set"); // TODO: Change to typed error

        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        require(delegatorSummary.delegated >= amount.to8Decimals(), "Insufficient delegated balance"); // TODO: Change to typed error

        // Immediately undelegate HYPE
        stakingVault.tokenDelegate(defaultValidator, amount.to8Decimals(), true);

        // Queue a staking withdrawal, subject to the 7-day withdrawal queue. Amount will be available in
        // the StakingVault's spot account balance after 7 days.
        stakingVault.stakingWithdraw(amount.to8Decimals());
        emit EmergencyStakingWithdraw(msg.sender, amount, purpose);
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @dev Function to receive HYPE when msg.data is empty
    receive() external payable {}

    /// @dev Fallback function to receive HYPE when msg.data is not empty
    fallback() external payable {}

    modifier onlyOperator() {
        require(roleRegistry.hasRole(roleRegistry.OPERATOR_ROLE(), msg.sender), "Caller is not an operator"); // TODO: Change to typed error
        _;
    }

    modifier onlyOwner() {
        require(roleRegistry.owner() == msg.sender, "Caller is not the owner"); // TODO: Change to typed error
        _;
    }

    modifier canDeposit() {
        // We prevent deposits for one block if there was a HyperEVM -> HyperCore transfer that happened earlier
        // in the block. When a HyperEVM -> HyperCore transfer occurs, the account balance state changes are not
        // reflected via L1Read precompiles until the beginning of the next block.
        require(block.number > lastHyperCoreTransferBlockNumber + 1, "Cannot deposit until the next block");
        uint256 balance = totalBalance();
        require(balance < vaultCapacity, "Vault is full"); // TODO: Change to typed error
        require(remainingDepositLimit(msg.sender) > 0, "Deposit limit reached"); // TODO: Change to typed error
        _;
    }

    modifier whenNotPaused() {
        require(!roleRegistry.isPaused(address(this)), "Contract is paused"); // TODO: Change to typed error
        _;
    }
}
