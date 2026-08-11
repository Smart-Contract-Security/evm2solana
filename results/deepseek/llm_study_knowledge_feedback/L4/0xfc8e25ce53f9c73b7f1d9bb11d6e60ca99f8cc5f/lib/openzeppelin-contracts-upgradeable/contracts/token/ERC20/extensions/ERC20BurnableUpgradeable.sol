// SPDX-License-Identifier: MIT

import {ERC20Upgradeable} from "../ERC20Upgradeable.sol";
import {ContextUpgradeable} from "../../../utils/ContextUpgradeable.sol";
import {Initializable} from "../../../proxy/utils/Initializable.sol";

abstract contract ERC20BurnableUpgradeable is Initializable, ContextUpgradeable, ERC20Upgradeable {
    function __ERC20Burnable_init() internal onlyInitializing {
    }

    function __ERC20Burnable_init_unchained() internal onlyInitializing {
    }

    function burn(uint64 value) public virtual {
        _burn(ContextUpgradeable._msgSender(), value);
    }

    function burnFrom(address account, uint64 value) public virtual {
        _spendAllowance(account, ContextUpgradeable._msgSender(), value);
        _burn(account, value);
    }
}