// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ImpactToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 private _customDecimals;

    constructor(uint256 initialSupply) ERC20("ImpactToken", "IMPT") {
        _customDecimals = uint8(18);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        
      _mint(msg.sender, initialSupply * (10 ** uint256(_customDecimals)));
    
    }

    
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }
  
}
