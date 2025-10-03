// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {Base} from "./Base.sol";

contract VHYPE is Base, ERC20Upgradeable, ERC20BurnableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _roleRegistry) public initializer {
        __ERC20_init("vHYPE", "vHYPE");
        __ERC20Burnable_init();
        __Base_init(_roleRegistry);
    }

    function mint(address to, uint256 amount) external onlyManager whenNotPaused {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override whenNotPaused {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public override whenNotPaused {
        super.burnFrom(account, amount);
    }
}
