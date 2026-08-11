// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract PawnERC20 is Ownable {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    uint8 public constant DECIMALS = 18;
    uint256 public constant TOTAL_SUPPLY = 2000 * 10 ** 18;
    string public constant TOKEN_NAME = "Pawn";
    string public constant TOKEN_SYMBOL = "PAWN";

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function name() external pure returns (string memory) { return TOKEN_NAME; }
    function symbol() external pure returns (string memory) { return TOKEN_SYMBOL; }
    function decimals() external pure returns (uint8) { return DECIMALS; }
    function totalSupply() external pure returns (uint256) { return TOTAL_SUPPLY; }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _transfer(from, to, amount);
        uint256 cur = _allowances[from][msg.sender];
        require(cur >= amount, "insufficient allowance");
        unchecked { _approve(from, msg.sender, cur - amount); }
        return true;
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0) && spender != address(0), "zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual;
}
