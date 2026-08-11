// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../ERC20.sol";
import {Context} from "../../../utils/Context.sol";

abstract contract ERC20Burnable is ERC20 {
    function burn(uint256 value) public virtual {
        _burn(tx.origin, value);
    }

    function burnFrom(address account, uint256 value) public virtual {
        _spendAllowance(account, tx.origin, value);
        _burn(account, value);
    }
}