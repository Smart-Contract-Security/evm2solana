// SPDX-License-Identifier: MIT

import 'solana';

contract SeerdexToken {
    uint128 public constant projectDevReserve = 4_800_000_000 * 10**18;
    uint128 public constant ecosystemRewardsReserve = 3_000_000_000 * 10**18;
    uint128 public constant marketingReserve = 8_000_000_000 * 10**18;
    uint128 public constant stakingReserve = 1_200_000_000 * 10**18;
    uint128 public constant liquidityReserve = 3_000_000_000 * 10**18;

    mapping(address => uint128) private _balances;
    mapping(address => mapping(address => uint128)) private _allowances;

    uint128 private _totalSupply;

    string private _name;
    string private _symbol;

    event Transfer(address indexed from, address indexed to, uint128 value);
    event Approval(address indexed owner, address indexed spender, uint128 value);

    constructor() {
        _name = "SeerDEX";
        _symbol = "SEERX";

        // Solana addresses are 32-byte keys. We use bytes32 literals.
        address projectDev = address(bytes32(hex"D70d42541442c5346E23ad0c9ea4ac920CD86aF8"));
        address ecosystemRewards = address(bytes32(hex"bbE49D16F2230F8E77A3fCEFafc5FA4D6d5B16b3"));
        address marketing = address(bytes32(hex"95379217e5f5AFA92A87db01F9F9a2584d25B433"));
        address staking = address(bytes32(hex"79DA67894228Dd7360c1aD88F02424453EfbF24b"));
        address liquidity = address(bytes32(hex"E049e4cf8C758D9573506A204354b8f2dBcd7228"));

        _mint(projectDev, projectDevReserve);
        _mint(ecosystemRewards, ecosystemRewardsReserve);
        _mint(marketing, marketingReserve);
        _mint(staking, stakingReserve);
        _mint(liquidity, liquidityReserve);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint128) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint128) {
        return _balances[account];
    }

    function transfer(address to, uint128 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint128) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint128 amount) public returns (bool) {
        address owner = tx.accounts.dataAccount.key;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint128 amount) public returns (bool) {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function burn(uint128 amount) public {
        address account = tx.accounts.dataAccount.key;
        _burn(account, amount);
    }

    function burnFrom(address account, uint128 amount) public {
        address spender = tx.accounts.dataAccount.key;
        _spendAllowance(account, spender, amount);
        _burn(account, amount);
    }

    function _transfer(address from, address to, uint128 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint128 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint128 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint128 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint128 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint128 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint128 amount) internal {
        uint128 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint128).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }
}