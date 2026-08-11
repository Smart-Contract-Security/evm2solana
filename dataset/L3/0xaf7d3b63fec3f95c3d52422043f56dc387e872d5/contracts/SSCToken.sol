// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title  SSCToken — Super System Chain ($SSC)
/// @notice Plain ERC-20, fixed supply 8B. No owner, no pause, no mint,
///         no signature surface. Fully decentralized.
contract SSCToken is ERC20 {

    uint256 public constant MAX_SUPPLY = 8_000_000_000 * 10**18;

    event TokensBurned(address indexed from, uint256 amount);

    constructor() ERC20("Super System Chain", "SSC") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    /// @notice Burn caller's tokens — sent to address(0), totalSupply decreases.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }
}
