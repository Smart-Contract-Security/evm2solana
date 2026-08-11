// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Collusion-Resistant Impartial Selection Protocol ($CRISP)
/// @notice Bare ERC20. No taxes, no transfer hooks — the *pool's* V4 hook is where the
///         CRISP governance lives, not the token. This keeps the token simple and lets the
///         secret-ballot fee mechanism live entirely at the pool layer.
contract CRISPToken is ERC20 {
    constructor(address recipient)
        ERC20("Collusion-Resistant Impartial Selection Protocol", "CRISP")
    {
        _mint(recipient, 1_000_000_000 ether); // 1B supply, all to deployer for LP
    }
}
