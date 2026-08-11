// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract BrainERC20 is ERC20, Ownable {
    uint256 private constant MAX_SUPPLY = 1000000 * 10 ** 18;

    constructor(string memory name, string memory symbol, uint256 initialSupply, address owner) ERC20(name, symbol) Ownable(owner) {
        transferOwnership(owner);
        require(initialSupply <= MAX_SUPPLY, "Initial supply exceeds maximum supply");
        _mint(owner, initialSupply);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Minting would exceed max supply");
        _mint(account, amount);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(_msgSender(), amount);
    }
}
