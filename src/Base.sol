// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {RoleRegistry} from "./RoleRegistry.sol";

contract Base is Initializable, UUPSUpgradeable {
    /// @notice Thrown if an action is attempted while the contract is paused.
    error Paused(address contractAddress);

    RoleRegistry public roleRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __Base_init(address _roleRegistry) internal onlyInitializing {
        __UUPSUpgradeable_init();
        roleRegistry = RoleRegistry(_roleRegistry);
    }

    modifier whenNotPaused() {
        require(!roleRegistry.isPaused(address(this)), Paused(address(this)));
        _;
    }

    modifier onlyManager() {
        require(
            roleRegistry.hasRole(roleRegistry.MANAGER_ROLE(), msg.sender),
            IAccessControl.AccessControlUnauthorizedAccount(msg.sender, roleRegistry.MANAGER_ROLE())
        );
        _;
    }

    modifier onlyOperator() {
        require(
            roleRegistry.hasRole(roleRegistry.OPERATOR_ROLE(), msg.sender),
            IAccessControl.AccessControlUnauthorizedAccount(msg.sender, roleRegistry.OPERATOR_ROLE())
        );
        _;
    }

    modifier onlyOwner() {
        require(roleRegistry.owner() == msg.sender, OwnableUpgradeable.OwnableUnauthorizedAccount(msg.sender));
        _;
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
