// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ProtocolRegistry} from "./ProtocolRegistry.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VHYPE} from "./VHYPE.sol";
import {Converters} from "./libraries/Converters.sol";

contract GenesisVaultManager is Initializable, UUPSUpgradeable {
    using Converters for *;

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// @dev The default validator to delegate HYPE to
    address public defaultValidator;

    ProtocolRegistry public protocolRegistry;
    VHYPE public vHYPE;
    IStakingVault public stakingVault;

    /// @notice The total HYPE capacity of the vault (in 18 decimals)
    /// @dev This is the total amount of HYPE that can be deposited into the vault.
    /// @dev All HYPE will be moved to the vault's staking account and staked with validators (on HyperCore).
    uint256 public vaultCapacity;

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
        address _protocolRegistry,
        address _vHYPE,
        address _stakingVault,
        uint256 _vaultCapacity,
        address _defaultValidator
    ) public initializer {
        __UUPSUpgradeable_init();

        protocolRegistry = ProtocolRegistry(_protocolRegistry);
        vHYPE = VHYPE(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        vaultCapacity = _vaultCapacity;
        defaultValidator = _defaultValidator;
    }

    /// @notice Deposits HYPE into the vault, and mints the equivalent amount of vHYPE. Refunds any excess HYPE if only a partial deposit is made. Reverts if the vault is full.
    function deposit() public payable canDeposit {
        uint256 requestedDepositAmount = msg.value;
        uint256 availableCapacity = vaultCapacity - totalBalance();
        uint256 amountToDeposit =
            requestedDepositAmount > availableCapacity ? availableCapacity : requestedDepositAmount;

        // Mint vHYPE
        // IMPORTANT: We need to make sure that we mint the vHYPE _before_ transferring the HYPE to the staking vault,
        // otherwise the exchange rate will be incorrect. We want the exchange rate to be calculated based on the total
        // HYPE in the vault _before_ the deposit
        uint256 amountToMint = HYPETovHYPE(amountToDeposit);
        vHYPE.mint(msg.sender, amountToMint);

        // Stake HYPE
        if (amountToDeposit > 0) {
            (bool success,) = payable(address(stakingVault)).call{value: amountToDeposit}(""); // HyperEVM -> HyperEVM
            require(success, "Transfer failed"); // TODO: Change to typed error

            stakingVault.transferHypeToCore(amountToDeposit); // HyperEVM -> HyperCore spot
            stakingVault.stakingDeposit(amountToDeposit.to8Decimals()); // HyperCore spot -> HyperCore staking
            stakingVault.tokenDelegate(defaultValidator, amountToDeposit.to8Decimals(), false); // Delegate HYPE to validator (from HyperCore staking)
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

    modifier onlyOwner() {
        require(protocolRegistry.owner() == msg.sender, "Caller is not the owner"); // TODO: Change to typed error
        _;
    }

    modifier canDeposit() {
        uint256 balance = totalBalance();
        require(balance < vaultCapacity, "Vault is full"); // TODO: Change to typed error
        _;
    }
}
