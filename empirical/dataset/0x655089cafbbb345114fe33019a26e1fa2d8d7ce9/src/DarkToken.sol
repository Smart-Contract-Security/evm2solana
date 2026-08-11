// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20}            from "solady/src/tokens/ERC20.sol";
import {Ownable}          from "solady/src/auth/Ownable.sol";
import {IDarkTokenHook}   from "./IDarkTokenHook.sol";

// =============================================================================
//
//                        ╔══════════════════════════════╗
//                        ║      D A R K   C R Y S T A L  ║
//                        ║                                ║
//                        ║          $DARK                 ║
//                        ║    Enter the darkness          ║
//                        ╚══════════════════════════════╝
//
//   $DARK is the energy that fuels the Crystal Forge.
//
//   The lore: a thousand-million shards of dark energy, scattered across the
//   void by an ancient cataclysm. The only way to reforge them into a
//   crystallized form is to bond them with ether at the Forge.
//
//   The mechanics: 1B DARK, fixed supply, single-side V4 LP at launch, no tax
//   on transfers. The V4 hook taxes 1% of every BUY and routes it to the
//   Crystal Forge, where it accrues to Dark Crystal NFT holders pro-rata by
//   their bonded power.
//
//   Burn the crystals to reclaim ETH (with a tribute to the remaining
//   holders). Hold them, and your share of the swap-tax stream grows every
//   time another holder shatters out.
//
// =============================================================================

contract DarkToken is ERC20, Ownable, IDarkTokenHook {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18;

    address public pool;
    address public hook;

    event PoolStarted(address indexed pool);
    event HookSet(address indexed hook);

    constructor(address owner_) {
        _initializeOwner(owner_);
        _mint(owner_, INITIAL_SUPPLY);
    }

    function name()   public pure override returns (string memory) { return "Dark Crystal"; }
    function symbol() public pure override returns (string memory) { return "DARK"; }

    function setHook(address newHook) external onlyOwner {
        require(!isStarted(), "cannot change hook after launch");
        require(newHook != address(0), "zero hook");
        hook = newHook;
        emit HookSet(newHook);
    }

    function start(address newPool) external onlyHook {
        require(!isStarted(), "already started");
        require(newPool != address(0), "zero pool");
        pool = newPool;
        emit PoolStarted(newPool);
    }

    function isStarted() public view returns (bool) { return pool != address(0); }

    modifier onlyHook() {
        require(msg.sender == hook, "only hook");
        _;
    }
}
