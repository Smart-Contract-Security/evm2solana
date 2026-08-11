// SPDX-License-Identifier: MIT

import 'solana';

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view returns (uint64) {
        return 0;
    }
}

abstract contract ERC20 is Context, IERC20, IERC20Metadata {
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
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        _update(from, to, value);
    }

    function _update(address from, address to, uint64 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint64 fromBalance = _balances[from];
            require(fromBalance >= value, "ERC20: insufficient balance");
            _balances[from] = fromBalance - value;
        }

        if (to == address(0)) {
            _totalSupply -= value;
        } else {
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        require(account != address(0), "ERC20: mint to zero address");
        _update(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        require(account != address(0), "ERC20: burn from zero address");
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint64 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal virtual {
        require(owner != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 value) internal virtual {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - value, false);
        }
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: invalid owner");
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: unauthorized");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: invalid owner");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ERC20Burnable is Context, ERC20 {
    function burn(uint64 value) public virtual {
        _burn(_msgSender(), value);
    }

    function burnFrom(address account, uint64 value) public virtual {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }
}

@program_id("SmileShare11111111111111111111111111111111")
contract SmileShare is ERC20, ERC20Burnable, Ownable {
    @payer(payer)
    @space(512)
    @seed("smile_share")
    constructor(address initialOwner, address payer)
        ERC20("Smile Share", "SMILE")
        Ownable(initialOwner)
    {
        _mint(owner(), 120000000000000);
    }
}