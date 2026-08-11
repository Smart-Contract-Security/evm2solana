// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract Dryad {

    string public constant name     = "Dryad";
    string public constant symbol   = "DRAD";
    uint8  public constant decimals = 18;

    uint256 public totalSupply;
    uint256 public totalBurned;

    uint256 public constant BURN_RATE_NUMERATOR   = 1;
    uint256 public constant BURN_RATE_DENOMINATOR = 10_000;

    address public constant BURN_VAULT = 0x000000000000000000000000000000000000dEaD;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to,       uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed from, uint256 value);

    constructor() {
        uint256 initialSupply = 1048785746661474828350921;
        totalSupply           = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "DRAD: approve to zero address");
        if (amount != 0 && allowance[msg.sender][spender] != 0) {
            allowance[msg.sender][spender] = 0;
            emit Approval(msg.sender, spender, 0);
        }
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        require(spender != address(0), "DRAD: approve to zero address");
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(spender != address(0), "DRAD: approve to zero address");
        uint256 current = allowance[msg.sender][spender];
        require(current >= subtractedValue, "DRAD: decreased allowance below zero");
        allowance[msg.sender][spender] = current - subtractedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "DRAD: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "DRAD: burn amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        totalSupply            -= amount;
        totalBurned            += amount;
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    function burnVaultBalance() external {
        uint256 amount = balanceOf[BURN_VAULT];
        require(amount > 0, "DRAD: vault is empty");
        balanceOf[BURN_VAULT] = 0;
        totalSupply           -= amount;
        totalBurned           += amount;
        emit Burn(BURN_VAULT, amount);
        emit Transfer(BURN_VAULT, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "DRAD: transfer from zero address");
        require(to   != address(0), "DRAD: transfer to zero address");
        require(balanceOf[from] >= amount, "DRAD: insufficient balance");

        uint256 feeAmount  = (amount * BURN_RATE_NUMERATOR) / BURN_RATE_DENOMINATOR;
        uint256 sendAmount = amount - feeAmount;

        balanceOf[from]      -= amount;
        balanceOf[to]        += sendAmount;
        balanceOf[BURN_VAULT] += feeAmount;

        if (feeAmount > 0) {
            emit Transfer(from, BURN_VAULT, feeAmount);
        }

        emit Transfer(from, to, sendAmount);
    }
}