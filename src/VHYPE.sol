// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Base} from "./Base.sol";

contract VHYPE is Base, ERC20Upgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _roleRegistry) public initializer {
        __ERC20_init("vHYPE", "vHYPE");
        __Base_init(_roleRegistry);
    }

    function mint(address to, uint256 amount) public onlyManager {
        _mint(to, amount);
    }
}
