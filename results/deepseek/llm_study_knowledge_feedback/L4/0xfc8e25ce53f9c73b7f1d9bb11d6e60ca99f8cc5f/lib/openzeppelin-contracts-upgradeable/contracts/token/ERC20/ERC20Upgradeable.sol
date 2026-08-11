// SPDX-License-Identifier: MIT

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "../../proxy/utils/Initializable.sol";

abstract contract ERC20Upgradeable is Initializable, IERC20, IERC20Metadata {
    struct ERC20Storage {
        mapping(address => uint64) _balances;
        mapping(address => mapping(address => uint64)) _allowances;
        uint64 _totalSupply;
        string _name;
        string _symbol;
    }

    bytes32 private constant ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getERC20Storage() private view returns (ERC20Storage storage $) {
        assembly {
            $.slot := ERC20StorageLocation
        }
    }

    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        ERC20Storage storage $ = _getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._name;
    }

    function symbol() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint64) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint64) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._balances[account];
    }

    function transfer(address to, uint64 value) public virtual returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint64) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._allowances[owner][spender];
    }

    function approve(address spender, uint64 value) public virtual returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) public virtual returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint64 value) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _update(from, to, value);
    }

    function _update(address from, address to, uint64 value) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        if (from == address(0)) {
            $._totalSupply += value;
        } else {
            uint64 fromBalance = $._balances[from];
            require(fromBalance >= value, "ERC20: transfer amount exceeds balance");
            unchecked {
                $._balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                $._totalSupply -= value;
            }
        } else {
            unchecked {
                $._balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _update(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint64 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        $._allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 value) internal virtual {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint64).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}