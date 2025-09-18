// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Base} from "./Base.sol";

contract StakingVault is IStakingVault, Base {
    address public immutable HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    /// @dev The last block number when HYPE was transferred from HyperEVM to HyperCore
    /// @dev Used to enforce a one-block delay between HyperEVM -> HyperCore transfers and deposits
    uint256 public lastEvmToCoreTransferBlockNumber;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _roleRegistry) public initializer {
        __Base_init(_roleRegistry);
    }

    /// @inheritdoc IStakingVault
    function deposit() external payable onlyManager whenNotPaused {
        // IMPORTANT: We enforce a one-block delay after a HyperEVM -> HyperCore transfer. This is to ensure that
        // the account balances after the transfer are reflected in L1Read precompiles before subsequent deposits
        // are made. Without this enforcement, subsequent deposits that occur in the same block as the transfer
        // would be made against an incorrect balance (and thus an incorrect exchange rate).
        require(block.number > lastEvmToCoreTransferBlockNumber, CannotDepositUntilNextBlock());
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
    function spotBalance(uint64 tokenId) external view returns (L1ReadLibrary.SpotBalance memory) {
        return L1ReadLibrary.spotBalance(address(this), tokenId);
    }

    /// @notice Internal function to handle HYPE transfers from the vault.
    /// @dev Reverts if there is not enought HYPE to transfer the requested amount, or if the underlying call fails.
    function _transfer(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientHYPEBalance();

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
    }
}
