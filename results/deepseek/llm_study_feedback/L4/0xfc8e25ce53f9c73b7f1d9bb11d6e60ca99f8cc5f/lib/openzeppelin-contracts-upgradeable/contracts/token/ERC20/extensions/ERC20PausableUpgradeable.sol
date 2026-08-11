// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "../../../proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "../../../utils/PausableUpgradeable.sol";

abstract contract ERC20PausableUpgradeable is Initializable, PausableUpgradeable {
    function __ERC20Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __ERC20Pausable_init_unchained() internal onlyInitializing {
    }

    function _update(address from, address to, uint256 value) internal virtual whenNotPaused {
        super._update(from, to, value);
    }
}