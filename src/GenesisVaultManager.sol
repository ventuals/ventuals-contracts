// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ProtocolRegistry} from "./ProtocolRegistry.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";

contract GenesisVaultManager is Initializable, UUPSUpgradeable {
    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    ProtocolRegistry public protocolRegistry;
    IERC20 public vHYPE;
    IStakingVault public stakingVault;

    /// @notice The total HYPE capacity of the vault (in 18 decimals)
    /// @dev This is the total amount of HYPE that can be deposited into the vault.
    /// @dev All HYPE will be moved to the vault's staking account and staked with validators (on HyperCore), except for the evmReserve amount (on HyperEVM).
    uint256 public vaultCapacity;

    /// @notice The HYPE amount to keep in the vault's EVM account (in 18 decimals)
    /// @dev This is the amount of HYPE to keep in the vault's EVM account (on HyperEVM)
    /// @dev This amount will not be transferred to the vault's staking account, nor staked with validators.
    uint256 public evmReserve;

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
        uint256 _evmReserve
    ) public initializer {
        __UUPSUpgradeable_init();

        protocolRegistry = ProtocolRegistry(_protocolRegistry);
        vHYPE = IERC20(_vHYPE);
        stakingVault = IStakingVault(payable(_stakingVault));

        vaultCapacity = _vaultCapacity;
        evmReserve = _evmReserve;
    }

    function deposit() public payable {
        revert("TODO: Not implemented");
    }

    /// @notice Returns the exchange rate of vHYPE to HYPE (in 18 decimals)
    /// @dev Ratio of vHYPE to total HYPE in the staking vault
    function exchangeRate() public view returns (uint256) {
        uint256 balance = totalBalance();
        if (balance == 0) {
            return 0;
        }
        return vHYPE.totalSupply() * 1e18 / balance;
    }

    /// @notice Returns the total HYPE balance in the vault (in 18 decimals)
    /// @dev Sum of staking account balance (on HyperCore), spot account balance (on HyperCore), and contract balance (on HyperEVM)
    function totalBalance() public view returns (uint256) {
        return stakingAccountBalance() + spotAccountBalance() + address(stakingVault).balance;
    }

    /// @notice Total HYPE balance in the staking vault's staking account balance (in 18 decimals)
    /// @dev Uses L1Read precompiles to get the delegator summary for the staking vault from HyperCore
    function stakingAccountBalance() public view returns (uint256) {
        L1ReadLibrary.DelegatorSummary memory delegatorSummary = stakingVault.delegatorSummary();
        return _convertTo18Decimals(delegatorSummary.delegated) + _convertTo18Decimals(delegatorSummary.undelegated)
            + _convertTo18Decimals(delegatorSummary.totalPendingWithdrawal);
    }

    /// @notice Total HYPE balance in the staking vault's spot account balance (in 18 decimals)
    /// @dev Uses L1Read precompiles to get the spot balance for the staking vault from HyperCore
    function spotAccountBalance() public view returns (uint256) {
        L1ReadLibrary.SpotBalance memory spotBalance = stakingVault.spotBalance(HYPE_TOKEN_ID);
        return _convertTo18Decimals(spotBalance.total);
    }

    /// @notice Sets the vault capacity (in 18 decimals)
    /// @dev Vault capacity is the total amount of HYPE that can be deposited into the staking vault
    function setVaultCapacity(uint256 _vaultCapacity) public onlyOwner {
        require(_vaultCapacity > evmReserve, "Vault capacity must be greater than EVM reserve"); // TODO: Change to typed error
        vaultCapacity = _vaultCapacity;
    }

    /// @notice Sets the EVM reserve (in 18 decimals)
    /// @dev EVM reserve is the amount of HYPE to keep in the vault's EVM account (on HyperEVM)
    function setEvmReserve(uint256 _evmReserve) public onlyOwner {
        require(_evmReserve < vaultCapacity, "EVM reserve must be less than vault capacity"); // TODO: Change to typed error
        evmReserve = _evmReserve;
    }

    /// @dev Convert an amount from 8 decimals to 18 decimals. Used for converting HYPE values from HyperCore to 18 decimals.
    function _convertTo18Decimals(uint64 amount) internal pure returns (uint256) {
        return uint256(amount) * 1e10;
    }

    /// @dev Function to receive HYPE when msg.data is empty
    receive() external payable {}

    /// @dev Fallback function to receive HYPE when msg.data is not empty
    fallback() external payable {}

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyOwner() {
        require(protocolRegistry.owner() == msg.sender, "Caller is not the owner"); // TODO: Change to typed error
        _;
    }
}
