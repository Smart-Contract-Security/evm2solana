// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC20/ERC20Base.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../templates/ERC20/ERC20Mintable.sol";

contract ERC20_mintable is
  ERC20Base,
  ERC20MintableFeature
{
  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply_, address initialOwner_)
    ERC20Base(name_, symbol_, decimals_, initialSupply_, initialOwner_)
  {
    _grantRole(MINTER_ROLE, msg.sender);
  }

  function _mintFeature(address to, uint256 amount) internal override {
    _mint(to, amount);
  }
}
