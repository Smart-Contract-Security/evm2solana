// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract USDC is ERC20, Ownable, ERC20Permit {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC20("USD Coin Test", "tUSDC") ERC20Permit("tUSDC") Ownable(msg.sender) {
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }
    
    function burnFrom(address account, uint256 value) public {
        _burn(account, value);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
