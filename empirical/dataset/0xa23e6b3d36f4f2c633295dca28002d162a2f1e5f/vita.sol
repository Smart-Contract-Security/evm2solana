// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ╔═══════════════════════════════════════════════════════════════════════════════════╗
// ║                                                                                   ║
// ║   ████████╗ █████╗ ███╗   ███╗ █████╗ ███████╗██╗    ██╗ █████╗ ██████╗           ║
// ║   ╚══██╔══╝██╔══██╗████╗ ████║██╔══██╗██╔════╝██║    ██║██╔══██╗██╔══██╗          ║
// ║      ██║   ███████║██╔████╔██║███████║███████╗██║ █╗ ██║███████║██████╔╝          ║
// ║      ██║   ██╔══██║██║╚██╔╝██║██╔══██║╚════██║██║███╗██║██╔══██║██╔═══╝           ║
// ║      ██║   ██║  ██║██║ ╚═╝ ██║██║  ██║███████║╚███╔███╔╝██║  ██║██║               ║
// ║      ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝               ║
// ║                                                                                   ║
// ║   the first provably unhackable DEX                                               ║
// ║   ──────────────────────────────────────────────────────────────────────          ║
// ║                                                                                   ║
// ║     ◆ No-free-lunch theorem, machine-checked via Lean                             ║
// ║     ◆ Onchain HTML interface, forever online                                      ║
// ║     ◆ No protocol fees, no-code deploy to any EVM chain                           ║
// ║                                                                                   ║
// ║   Built with Tama + Verity.  AGPL license.                                        ║
// ║                                                                                   ║
// ║                            x · y = k                                              ║
// ║                   the platonic ideal of constant product                          ║
// ║                                                                                   ║
// ║   ──────────────────────────────────────────────────────────────────────          ║
// ║                                                                                   ║
// ║ X Announcement →  https://x.com/boredGenius/status/2060094391667372464            ║
// ║ Website  →        https://0x000000b6c9f43311303ae28d995de7fe9b266cd4.1.w3link.io/ ║
// ║                                                                                   ║
// ╚═══════════════════════════════════════════════════════════════════════════════════╝



interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
}

/// @dev V4 packs two int128 token deltas into one int256. We unpack by hand.
type BalanceDelta is int256;

/// @dev V4's pool identity — the genetic address of a market.
struct PoolKey {
    address currency0;
    address currency1;
    uint24  fee;
    int24   tickSpacing;
    address hooks;
}




import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TamaSwap is ERC20, ERC20Burnable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("TamaSwap", "TAMA") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
