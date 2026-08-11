// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}   from "solady/src/tokens/ERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

// =============================================================================
//
//   $DARK — Dark Crystal (v2, Uniswap V2 launch)
//
//   "Enter the darkness."
//
//   Telegram : https://t.me/darkcrystalportal
//   X        : https://x.com/DarkCrystalERC
//   Web      : https://dark-crystal-dapp.vercel.app
//
//   Plain ERC-20 on Ethereum mainnet. 1B supply, 18 decimals, no transfer tax,
//   no admin function past renouncing ownership. Paired against ETH on
//   Uniswap V2 at launch.
//
//   Tokenomics
//   ──────────
//   Total supply  : 1,000,000,000 $DARK
//   Decimals      : 18
//   LP (V2)       : 70% (700M DARK + 1 ETH paired)
//   Rewards pool  : 30% (300M DARK streaming over 90 days via DarkRewardsV2)
//   Deployer hold : 0% — clean fair, nothing left over post-launch
//   Transfer tax  : zero
//
// =============================================================================

contract DarkTokenV2 is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18;

    constructor(address owner_) {
        _initializeOwner(owner_);
        _mint(owner_, INITIAL_SUPPLY);
    }

    function name()   public pure override returns (string memory) { return "Dark Crystal"; }
    function symbol() public pure override returns (string memory) { return "DARK"; }
}
