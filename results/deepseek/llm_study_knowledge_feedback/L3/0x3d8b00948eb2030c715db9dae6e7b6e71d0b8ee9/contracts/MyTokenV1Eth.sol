import {AccountMeta} from 'solana';

contract MyTokenV1Eth {
    uint8 private constant _DECIMALS = 18;
    uint64[49] private __gap;

    bool private initialized;
    address private _owner;
    string private _name;
    string private _symbol;
    uint64 private _totalSupply;
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier initializer() {
        require(!initialized, "Already initialized");
        initialized = true;
        _;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialRecipient,
        uint64 initialSupply
    ) public initializer {
        _name = name_;
        _symbol = symbol_;
        _owner = tx.accounts.dataAccount.key;
        _mint(initialRecipient, initialSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint64 amount) public returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint64 amount) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from zero");
        require(_balances[account] >= amount, "ERC20: insufficient balance");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint64 amount) internal {
        uint64 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint64).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function upgradeTo(address newImplementation) public onlyOwner {
        emit Upgraded(newImplementation);
    }

    event Upgraded(address indexed implementation);
}