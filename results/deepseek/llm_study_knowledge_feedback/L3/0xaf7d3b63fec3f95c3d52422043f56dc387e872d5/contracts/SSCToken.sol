import {AccountMeta} from 'solana';

@program_id("11111111111111111111111111111111")
contract SSCToken {
    uint64 public constant MAX_SUPPLY = 8000000000;

    uint64 private _totalSupply;
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event TokensBurned(address indexed from, uint64 amount);

    constructor() {
        _name = "Super System Chain";
        _symbol = "SSC";
        _decimals = 18;

        _mint(tx.accounts.dataAccount.key, MAX_SUPPLY);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address recipient, uint64 amount) external returns (bool) {
        _transfer(tx.accounts.dataAccount.key, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) external returns (bool) {
        _approve(tx.accounts.dataAccount.key, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool) {
        _spendAllowance(sender, tx.accounts.dataAccount.key, amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function increaseAllowance(address spender, uint64 addedValue) external returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue) external returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        uint64 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint64 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint64 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint64 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function burn(uint64 amount) external {
        _burn(tx.accounts.dataAccount.key, amount);
        emit TokensBurned(tx.accounts.dataAccount.key, amount);
    }
}