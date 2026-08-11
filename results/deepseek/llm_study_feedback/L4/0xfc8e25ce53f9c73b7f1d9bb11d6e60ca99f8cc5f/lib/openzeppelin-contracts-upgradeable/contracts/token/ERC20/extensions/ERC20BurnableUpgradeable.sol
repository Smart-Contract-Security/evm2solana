// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "../ERC20Upgradeable.sol";
import {ContextUpgradeable} from "../../../utils/ContextUpgradeable.sol";
import {Initializable} from "../../../proxy/utils/Initializable.sol";

abstract contract ERC20BurnableUpgradeable is Initializable, ContextUpgradeable, ERC20Upgradeable {
    function __ERC20Burnable_init() internal onlyInitializing {
    }

    function __ERC20Burnable_init_unchained() internal onlyInitializing {
    }

    function burn(uint256 value) public virtual {
        _burn(msg.sender, value);
    }

    function burnFrom(address account, uint256 value) public virtual {
        _spendAllowance(account, msg.sender, value);
        _burn(account, value);
    }
}