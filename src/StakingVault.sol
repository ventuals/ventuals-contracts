// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Base} from "./Base.sol";

contract StakingVault is IStakingVault, Base {
    /// @dev The HYPE system address
    address public immutable HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// @dev The last block number when HYPE was transferred from HyperEVM to HyperCore
    /// @dev Used to enforce a one-block delay between HyperEVM -> HyperCore transfers and deposits
    uint256 public lastEvmToCoreTransferBlockNumber;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint64 _hypeTokenId) {
        _disableInitializers();

        HYPE_TOKEN_ID = _hypeTokenId;
    }

    function initialize(address _roleRegistry) public initializer {
        __Base_init(_roleRegistry);
    }

    /// @inheritdoc IStakingVault
    function deposit() external payable onlyManager whenNotPaused {
        emit Deposit(msg.sender, msg.value);
    }

    /// @inheritdoc IStakingVault
    function stakingDeposit(uint64 weiAmount) external onlyManager whenNotPaused {
        CoreWriterLibrary.stakingDeposit(weiAmount);
    }

    /// @inheritdoc IStakingVault
    function stakingWithdraw(uint64 weiAmount) external onlyManager whenNotPaused {
        CoreWriterLibrary.stakingWithdraw(weiAmount);
    }

    /// @inheritdoc IStakingVault
    function tokenDelegate(address validator, uint64 weiAmount, bool isUndelegate) external onlyManager whenNotPaused {
        CoreWriterLibrary.tokenDelegate(validator, weiAmount, isUndelegate);
    }

    /// @inheritdoc IStakingVault
    function spotSend(address destination, uint64 token, uint64 weiAmount) external onlyManager whenNotPaused {
        CoreWriterLibrary.spotSend(destination, token, weiAmount);
    }

    /// @inheritdoc IStakingVault
    function transferHypeToCore(uint256 amount) external onlyManager whenNotPaused {
        require(block.number > lastEvmToCoreTransferBlockNumber, CannotTransferToCoreUntilNextBlock());

        // This is an important safety check - ensures that the StakingVault account is activated on HyperCore.
        // If the StakingVault is not activated on HyperCore, and a HyperEVM -> HyperCore HYPE transfer is made,
        // the transferred HYPE will be lost.
        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(address(this));
        if (!coreUserExists.exists) {
            revert NotActivatedOnHyperCore();
        }
        _transfer(payable(HYPE_SYSTEM_ADDRESS), amount);

        lastEvmToCoreTransferBlockNumber = block.number;
    }

    /// @inheritdoc IStakingVault
    function addApiWallet(address apiWalletAddress, string calldata name) external onlyOperator whenNotPaused {
        CoreWriterLibrary.addApiWallet(apiWalletAddress, name);
    }

    /// @inheritdoc IStakingVault
    function delegatorSummary() external view returns (L1ReadLibrary.DelegatorSummary memory) {
        return L1ReadLibrary.delegatorSummary(address(this));
    }

    /// @inheritdoc IStakingVault
    function isSpotBalanceSafe() public view returns (bool) {
        return block.number > lastEvmToCoreTransferBlockNumber;
    }

    /// @inheritdoc IStakingVault
    function spotBalance() public view returns (L1ReadLibrary.SpotBalance memory) {
        return L1ReadLibrary.spotBalance(address(this), HYPE_TOKEN_ID);
    }

    /// @notice Internal function to handle HYPE transfers from the vault.
    /// @dev Reverts if there is not enought HYPE to transfer the requested amount, or if the underlying call fails.
    function _transfer(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientHYPEBalance();

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
    }
}
