// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice $HOUSE — the Stablehouse protocol token.
///
/// Fixed supply, no minting after deploy, burnable. The buyback-and-burn
/// engine in Treasury reduces circulating supply as the protocol earns fees.
///
/// Distribution is handled at the application layer: the constructor mints
/// the full supply to `treasury_` (a multisig or the Treasury contract),
/// which then allocates per the team's plan (initial Uniswap liquidity,
/// vesting, etc.).
contract HouseToken is ERC20, ERC20Burnable {
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 18;

    constructor(address mintTo) ERC20("Stablehouse", "HOUSE") {
        require(mintTo != address(0), "zero mint target");
        _mint(mintTo, MAX_SUPPLY);
    }
}
