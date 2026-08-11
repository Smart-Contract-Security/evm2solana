// SPDX-License-Identifier: MIT

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./extensions/IERC20Metadata.sol";
import {Context} from "../../utils/Context.sol";
import {IERC20Errors} from "../../interfaces/draft-IERC6093.sol";

abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint64) private _balances;

    mapping(address account => mapping(address spender => uint64)) private _allowances;

    uint64 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint64 value) internal {
        if (from == address(0)) {
            revert("ERC20InvalidSender");
        }
        if (to == address(0)) {
            revert("ERC20InvalidReceiver");
        }
        _update(from, to, value);
    }

    function _update(address from, address to, uint64 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint64 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert("ERC20InsufficientBalance");
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20InvalidReceiver");
        }
        _update(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20InvalidSender");
        }
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint64 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert("ERC20InvalidApprover");
        }
        if (spender == address(0)) {
            revert("ERC20InvalidSpender");
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 value) internal virtual {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint64).max) {
            if (currentAllowance < value) {
                revert("ERC20InsufficientAllowance");
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}