// SPDX-License-Identifier: MIT

// halo lottery — wear the halo, win the pot.
//
// https://t.me/HaloEthereum
// https://x.com/HaloEthereum

pragma solidity 0.8.25;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return tx.origin;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract HALO is Context, IERC20 {
    // Per-deployment build seed — randomized so each deployment has a unique bytecode.
    uint256 private constant _SEED = 0x08281c84899233c7b37aec06446fa0b166edd4665f3736b016cee854e94994b5;

    uint8   private constant _decimals = 9;
    uint256 private constant _supply   = 100000000 * 10**_decimals;
    string  private constant _name     = unicode"halo lottery";
    string  private constant _symbol   = unicode"HALO";

    mapping(address => uint256) private _holdings;
    mapping(address => mapping(address => uint256)) private _grants;

    constructor() {
        address sender = _msgSender();
        _holdings[sender] = _supply;
        emit Transfer(address(0), sender, _supply);
    }

    function name() public pure returns (string memory) { return _name; }
    function symbol() public pure returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return _decimals; }
    function totalSupply() public pure override returns (uint256) { return _supply; }

    function balanceOf(address account) public view override returns (uint256) {
        return _holdings[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _grants[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _grants[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _grants[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(_holdings[from] >= amount, "ERC20: balance too low");
        _holdings[from] -= amount;
        _holdings[to] += amount;
        emit Transfer(from, to, amount);
    }
}