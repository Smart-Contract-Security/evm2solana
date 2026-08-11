// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../templates/ERC20/ERC20Base.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../templates/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../templates/ERC20/ERC20Pausable.sol";

contract ERC20_burnable_pausable is
  ERC20Base,
  ERC20BurnableFeature,
  ERC20PausableFeature
{
  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply_, address initialOwner_)
    ERC20Base(name_, symbol_, decimals_, initialSupply_, initialOwner_)
  {
    _grantRole(PAUSER_ROLE, msg.sender);
  }

  function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Pausable)
  {
    super._update(from, to, value);
  }

  function _hasRoleFeature(bytes32 role, address account) internal view override returns (bool) {
    return hasRole(role, account);
  }

  function decimals() public view override(ERC20, ERC20Base) returns (uint8) {
    return ERC20Base.decimals();
  }
}
