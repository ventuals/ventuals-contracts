// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Base} from "./Base.sol";

contract StakingVault is IStakingVault, Base {
    address public immutable HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    event Received(address indexed sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _roleRegistry) public initializer {
        __Base_init(_roleRegistry);
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
        _transfer(payable(HYPE_SYSTEM_ADDRESS), amount);
    }

    /// @inheritdoc IStakingVault
    function transferHype(address payable recipient, uint256 amount) external onlyManager whenNotPaused {
        _transfer(recipient, amount);
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

    /// @dev Function to receive HYPE when msg.data is empty
    receive() external payable virtual {
        emit Received(msg.sender, msg.value);
    }

    /// @dev Fallback function to receive HYPE when msg.data is not empty
    fallback() external payable virtual {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Internal function to handle HYPE transfers from the vault.
    /// @dev Reverts if there is not enought HYPE to transfer the requested amount, or if the underlying call fails.
    function _transfer(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientHYPEBalance();

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
    }
}
