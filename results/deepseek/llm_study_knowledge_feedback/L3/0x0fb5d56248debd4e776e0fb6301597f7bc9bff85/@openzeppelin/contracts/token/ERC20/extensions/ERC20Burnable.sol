// SPDX-License-Identifier: MIT

import {ERC20} from "../ERC20.sol";
import {Context} from "../../../utils/Context.sol";

abstract contract ERC20Burnable is Context, ERC20 {
    function burn(uint64 value) public virtual {
        _burn(_msgSender(), value);
    }

    function burnFrom(address account, uint64 value) public virtual {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }
}