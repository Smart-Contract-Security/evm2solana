// SPDX-License-Identifier: MIT
/*
  _     _       _     _       _           _            _    ___ 
 | |   (_) __ _| |__ | |_ ___| |__   __ _(_)_ __      / \  |_ _|
 | |   | |/ _` | '_ \| __/ __| '_ \ / _` | | '_ \    / _ \  | | 
 | |___| | (_| | | | | || (__| | | | (_| | | | | |  / ___ \ | | 
 |_____|_|\__, |_| |_|\__\___|_| |_|\__,_|_|_| |_| /_/   \_\___|
          |___/                                                 
*/

pragma solidity ^0.8.20;

contract LightchainAI {
    string public name = "LightchainAI";
    string public symbol = "LCAI";
    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 10_000_000_000 * 10 ** uint256(_decimals);

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BatchTransfer(address indexed from, address[] recipients, uint256[] amounts);

    constructor() {
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "Transfer from zero address");
        require(recipient != address(0), "Transfer to zero address");
        require(_balances[sender] >= amount, "Transfer amount exceeds balance");

        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero address");
        require(spender != address(0), "Approve to zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        require(recipients.length == amounts.length, "Mismatched input lengths");
        for (uint256 i = 0; i < recipients.length; ++i) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        emit BatchTransfer(msg.sender, recipients, amounts);
    }
}