// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC20/ERC20Base.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20_base is
  ERC20Base
{
  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply_, address initialOwner_)
    ERC20Base(name_, symbol_, decimals_, initialSupply_, initialOwner_)
  {
    
  }

}
