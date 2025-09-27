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

    /// @dev The last block number when HYPE was delegated or undelegated to a validator
    /// @dev This is used to enforce a minimum one-block delay between delegating/undelegating to a
    ///      validator, and reading the delegation state for the validator from the L1Read precompiles
    mapping(address => uint256) public lastDelegationChangeBlockNumber;

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
        require(msg.value > 0, ZeroAmount());
        emit Deposit(msg.sender, msg.value);
    }

    /// @inheritdoc IStakingVault
    function stakingDeposit(uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        CoreWriterLibrary.stakingDeposit(weiAmount);
    }

    /// @inheritdoc IStakingVault
    function stakingWithdraw(uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        CoreWriterLibrary.stakingWithdraw(weiAmount);
    }

    /// @inheritdoc IStakingVault
    function tokenDelegate(address validator, uint64 weiAmount) public onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        CoreWriterLibrary.tokenDelegate(validator, weiAmount, false);
        lastDelegationChangeBlockNumber[validator] = block.number;
    }

    /// @inheritdoc IStakingVault
    function tokenUndelegate(address validator, uint64 weiAmount) public onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());

        // Check if we have enough HYPE to undelegate
        (bool exists, L1ReadLibrary.Delegation memory delegation) = _getDelegation(validator);
        require(exists && delegation.amount >= weiAmount, InsufficientHYPEBalance());

        // Check if the stake is unlocked. This value will only be correct in the block after
        // a delegate action is processed.
        require(
            delegation.lockedUntilTimestamp <= block.timestamp,
            StakeLockedUntilTimestamp(validator, delegation.lockedUntilTimestamp)
        );

        CoreWriterLibrary.tokenDelegate(validator, weiAmount, true);

        // Update the last delegation change block number
        lastDelegationChangeBlockNumber[validator] = block.number;
    }

    /// @inheritdoc IStakingVault
    function tokenRedelegate(address fromValidator, address toValidator, uint64 weiAmount)
        external
        onlyManager
        whenNotPaused
    {
        require(weiAmount > 0, ZeroAmount());
        require(fromValidator != toValidator, RedelegateToSameValidator());

        tokenUndelegate(fromValidator, weiAmount); // Will revert if the stake is locked, or if the validator does not have enough HYPE to undelegate
        tokenDelegate(toValidator, weiAmount);
    }

    /// @inheritdoc IStakingVault
    function spotSend(address destination, uint64 token, uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        CoreWriterLibrary.spotSend(destination, token, weiAmount);
    }

    /// @inheritdoc IStakingVault
    function transferHypeToCore(uint256 amount) external onlyManager whenNotPaused {
        require(amount > 0, ZeroAmount());
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

    /// @notice Returns the delegation for a given validator
    /// @param _validator The validator to get the delegation for
    /// @return The delegation for the given validator
    function _getDelegation(address _validator) internal view returns (bool, L1ReadLibrary.Delegation memory) {
        // IMPORTANT: We enforce a one-block delay between delegating/undelegating to a validator and reading the
        // delegation state for the validator from the L1Read precompiles. This is to ensure that the delegation
        // state is updated in the L1Read precompiles before reading it.
        require(
            lastDelegationChangeBlockNumber[_validator] == 0
                || block.number > lastDelegationChangeBlockNumber[_validator] + 1,
            CannotReadDelegationUntilNextBlock()
        );

        L1ReadLibrary.Delegation[] memory delegations = L1ReadLibrary.delegations(address(this));
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].validator == _validator) {
                return (true, delegations[i]);
            }
        }
        return (false, L1ReadLibrary.Delegation({validator: address(0), amount: 0, lockedUntilTimestamp: 0}));
    }
}
