// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ICoreWriter} from "./interfaces/ICoreWriter.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {RoleRegistry} from "./RoleRegistry.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";

contract StakingVault is IStakingVault, Initializable, UUPSUpgradeable {
    address public immutable HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    RoleRegistry public roleRegistry;

    event Received(address indexed sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _roleRegistry) public initializer {
        __UUPSUpgradeable_init();

        roleRegistry = RoleRegistry(_roleRegistry);
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
        require(address(this).balance >= amount, "Staking vault does not have enough HYPE to transfer");

        (bool success,) = payable(HYPE_SYSTEM_ADDRESS).call{value: amount}("");
        require(success, "Failed to transfer HYPE to HyperCore"); // TODO: Change to typed error
    }

    /// @inheritdoc IStakingVault
    function transferHype(address payable recipient, uint256 amount) external onlyManager whenNotPaused {
        require(address(this).balance >= amount, "Staking vault does not have enough HYPE to transfer");

        (bool success,) = recipient.call{value: amount}("");
        require(success, "Transfer failed"); // TODO: Change to typed error
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
        require(!roleRegistry.isPaused(address(this)), "Contract is paused"); // TODO: Change to typed error
        _;
    }

    modifier onlyManager() {
        require(roleRegistry.hasRole(roleRegistry.MANAGER_ROLE(), msg.sender), "Caller is not a manager"); // TODO: Change to typed error
        _;
    }

    modifier onlyOperator() {
        require(roleRegistry.hasRole(roleRegistry.OPERATOR_ROLE(), msg.sender), "Caller is not an operator"); // TODO: Change to typed error
        _;
    }

    modifier onlyOwner() {
        require(roleRegistry.owner() == msg.sender, "Caller is not the owner"); // TODO: Change to typed error
        _;
    }

    /// @dev Function to receive HYPE when msg.data is empty
    receive() external payable virtual {
        emit Received(msg.sender, msg.value);
    }

    /// @dev Fallback function to receive HYPE when msg.data is not empty
    fallback() external payable virtual {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
