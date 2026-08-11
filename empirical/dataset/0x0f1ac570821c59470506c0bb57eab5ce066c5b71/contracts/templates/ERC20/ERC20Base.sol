// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract ERC20Base is ERC20, AccessControl {
    uint8 private immutable _customDecimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        address initialOwner_
    ) ERC20(name_, symbol_) {
        require(decimals_ <= 18, "decimals max 18");
        require(initialOwner_ != address(0), "invalid initial owner");

        _customDecimals = decimals_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        if (initialSupply_ > 0) {
            _mint(initialOwner_, initialSupply_);
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }
}