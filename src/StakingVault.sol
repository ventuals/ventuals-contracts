// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ICoreWriter} from "./interfaces/ICoreWriter.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {ProtocolRegistry} from "./ProtocolRegistry.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";

contract StakingVault is IStakingVault, Initializable, UUPSUpgradeable {
    ProtocolRegistry public protocolRegistry;

    event Received(address indexed sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _protocolRegistry) public initializer {
        __UUPSUpgradeable_init();

        protocolRegistry = ProtocolRegistry(_protocolRegistry);
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
    function transferHype(address payable recipient, uint256 amount) external onlyManager whenNotPaused {
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
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

    modifier whenNotPaused() {
        require(!protocolRegistry.isPaused(address(this)), "Contract is paused");
        _;
    }

    modifier onlyManager() {
        require(protocolRegistry.hasRole(protocolRegistry.MANAGER_ROLE(), msg.sender), "Caller is not a manager");
        _;
    }

    modifier onlyOperator() {
        require(protocolRegistry.hasRole(protocolRegistry.OPERATOR_ROLE(), msg.sender), "Caller is not an operator");
        _;
    }

    modifier onlyOwner() {
        require(protocolRegistry.owner() == msg.sender, "Caller is not the owner");
        _;
    }

    /// @dev Function to receive HYPE when msg.data is empty
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @dev Fallback function to receive HYPE when msg.data is not empty
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
