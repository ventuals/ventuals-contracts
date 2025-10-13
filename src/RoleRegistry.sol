// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {EnumerableRoles} from "solady/auth/EnumerableRoles.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract RoleRegistry is Initializable, EnumerableRoles, UUPSUpgradeable, Ownable2StepUpgradeable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(address => bool) private pausedContracts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(initialOwner);
    }

    /// @notice Grants a role to an account. Only the owner can grant a role.
    /// @param role The role to grant
    /// @param account The account to grant the role to
    function grantRole(bytes32 role, address account) external {
        // setRole will check that the msg.sender is the owner()
        setRole(account, uint256(role), true);
    }

    /// @notice Revokes a role from an account. Only the owner can revoke a role.
    /// @param role The role to revoke
    /// @param account The account to revoke the role from
    function revokeRole(bytes32 role, address account) external {
        // setRole will check that the msg.sender is the owner()
        setRole(account, uint256(role), false);
    }

    /// @notice Checks if an account has a role.
    /// @param role The role to check
    /// @param account The account to check the role for
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return super.hasRole(account, uint256(role));
    }

    /// @notice Returns the list of accounts that have a role.
    /// @param role The role to check
    /// @return The list of accounts that have the role
    function roleHolders(bytes32 role) public view returns (address[] memory) {
        return super.roleHolders(uint256(role));
    }

    /// @notice Checks if a contract is paused.
    /// @param contractAddress The address of the contract to check
    /// @return True if the contract is paused, false otherwise
    function isPaused(address contractAddress) public view returns (bool) {
        return pausedContracts[contractAddress];
    }

    /// @notice Pauses a contract. Only the owner can pause a contract.
    /// @dev The implementation of the contract should check if the contract is paused before executing pauseable functions
    /// @param contractAddress The address of the contract to pause
    function pause(address contractAddress) external onlyOwner {
        pausedContracts[contractAddress] = true;
    }

    /// @notice Unpauses a contract. Only the owner can unpause a contract.
    /// @dev The implementation of the contract should check if the contract is unpaused before executing pauseable functions
    /// @param contractAddress The address of the contract to unpause
    function unpause(address contractAddress) external onlyOwner {
        pausedContracts[contractAddress] = false;
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
