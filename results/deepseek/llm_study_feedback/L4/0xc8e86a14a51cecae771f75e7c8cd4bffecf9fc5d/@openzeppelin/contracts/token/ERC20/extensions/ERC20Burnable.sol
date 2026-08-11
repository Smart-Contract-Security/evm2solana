// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ERC20.sol";
import "../../../utils/Context.sol";

abstract contract ERC20Burnable is Context, ERC20 {
    function burn(uint256 amount) public virtual {
        _burn(tx.origin, amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, tx.origin, amount);
        _burn(account, amount);
    }
}