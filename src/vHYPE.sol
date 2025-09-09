// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ProtocolRegistry} from "./ProtocolRegistry.sol";

contract vHYPE is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, UUPSUpgradeable {
    ProtocolRegistry public protocolRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _protocolRegistry) public initializer {
        __ERC20_init("vHYPE", "vHYPE");
        __ERC20Burnable_init();

        protocolRegistry = ProtocolRegistry(_protocolRegistry);
    }

    function mint(address to, uint256 amount) public onlyManager {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override {
        _burn(msg.sender, amount);
    }

    modifier onlyManager() {
        require(protocolRegistry.hasRole(protocolRegistry.MANAGER_ROLE(), msg.sender), "Caller is not a manager");
        _;
    }

    modifier onlyOwner() {
        require(protocolRegistry.owner() == msg.sender, "Caller is not the owner");
        _;
    }

    /// @notice Authorizes an upgrade. Only the owner can authorize an upgrade.
    /// @dev DO NOT REMOVE THIS FUNCTION, OTHERWISE WE LOSE THE ABILITY TO UPGRADE THE CONTRACT
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
