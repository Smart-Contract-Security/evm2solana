// halo lottery — wear the halo, win the pot.
//
// https://t.me/HaloEthereum
// https://x.com/HaloEthereum

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

contract HALO is Context, IERC20 {
    uint64 private constant _decimals = 9;
    uint64 private constant _supply   = 100000000 * 10**_decimals;
    string  private constant _name     = unicode"halo lottery";
    string  private constant _symbol   = unicode"HALO";

    mapping(address => uint64) private _holdings;
    mapping(address => mapping(address => uint64)) private _grants;

    constructor() {
        address sender = _msgSender();
        _holdings[sender] = _supply;
        emit Transfer(address(0), sender, _supply);
    }

    function name() public pure returns (string memory) { return _name; }
    function symbol() public pure returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint64) { return _decimals; }
    function totalSupply() public pure override returns (uint64) { return _supply; }

    function balanceOf(address account) public view override returns (uint64) {
        return _holdings[account];
    }

    function transfer(address recipient, uint64 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint64) {
        return _grants[owner][spender];
    }

    function approve(address spender, uint64 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint64 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        uint64 currentAllowance = _grants[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function _approve(address owner, address spender, uint64 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _grants[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint64 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(_holdings[from] >= amount, "ERC20: balance too low");
        _holdings[from] -= amount;
        _holdings[to] += amount;
        emit Transfer(from, to, amount);
    }
}