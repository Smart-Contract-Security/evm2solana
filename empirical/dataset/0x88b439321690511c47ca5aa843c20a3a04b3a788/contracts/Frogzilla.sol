// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Frogzilla is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    uint256 public taxRate = 2;

    address public taxWallet = payable(0x3EDe12A6184E42AA636C0DcA7994A187cBE951e4);
    mapping(address => bool) private _isExcludedFromTax;

    constructor() ERC20("FROGZILLA", "FRGZ") {
        _mint(msg.sender, MAX_SUPPLY);
        _isExcludedFromTax[msg.sender] = true;
        _isExcludedFromTax[address(this)] = true;
        _isExcludedFromTax[taxWallet] = true;
    }

    function setTaxRate(uint256 newRate) external onlyOwner {
        require(newRate <= 10, "Tax too high");
        taxRate = newRate;
    }

    function setTaxWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        taxWallet = newWallet;
        _isExcludedFromTax[newWallet] = true;
    }

    function excludeFromTax(address account, bool excluded) external onlyOwner {
        _isExcludedFromTax[account] = excluded;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (_isExcludedFromTax[from] || _isExcludedFromTax[to]) {
            super._transfer(from, to, amount);
        } else {
            uint256 taxAmount = (amount * taxRate) / 100;
            uint256 afterTax = amount - taxAmount;

            super._transfer(from, taxWallet, taxAmount);
            super._transfer(from, to, afterTax);
        }
    }

    function renounceControl() external onlyOwner {
        renounceOwnership();
    }
}
