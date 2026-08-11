// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Dhow is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public isFrozen;
    event Frozen(address indexed target);
    event Unfrozen(address indexed target);

    constructor(address initialOwner)
        ERC20("Dhow", "DHOW")
        Ownable(initialOwner)
    {}

    function freezeAccount(address target) external onlyOwner {
        isFrozen[target] = true;
        emit Frozen(target);
    }

    function unfreezeAccount(address target) external onlyOwner {
        isFrozen[target] = false;
        emit Unfrozen(target);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) require(!isFrozen[from], "Sender frozen");
        if (to != address(0)) require(!isFrozen[to], "Recipient frozen");
        super._update(from, to, value);
    }
}