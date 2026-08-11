// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC20/ERC20Base.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../templates/ERC20/ERC20Burnable.sol";

contract ERC20_burnable is
  ERC20Base,
  ERC20BurnableFeature
{
  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply_, address initialOwner_)
    ERC20Base(name_, symbol_, decimals_, initialSupply_, initialOwner_)
  {
    
  }

  function decimals() public view override(ERC20, ERC20Base) returns (uint8) {
    return ERC20Base.decimals();
  }
}
