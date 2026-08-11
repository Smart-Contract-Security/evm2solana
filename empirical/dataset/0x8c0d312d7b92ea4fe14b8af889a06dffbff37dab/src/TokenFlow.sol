// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title TokenFlow (TFLO)
/// @notice 1B fixed-supply ERC20 with burn. 100% minted to the deployer at construction —
///         deployer is expected to seed the V4 TFLO/native-ETH pool via `LaunchpadV4` and then
///         hold no further admin role over the token (no mint, no pause, no owner).
contract TokenFlow is ERC20, ERC20Burnable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18;

    constructor() ERC20("TokenFlow", "TFLO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
