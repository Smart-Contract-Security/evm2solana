// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*//////////////////////////////////////////////////////////////////////////////////////////////
                                        INTERFOLD ($FOLD)

  Interfold is a coercion-resistant, holder-governed liquidity primitive. At its surface it is an
  ordinary ERC20 — no taxes, no rebases, no transfer hooks, no privileged mint after genesis — but
  the token is only the *visible fold* of a deeper construction. The entire governance surface
  lives one layer down, at the Uniswap V4 pool, where a dynamic-fee hook continuously folds the
  collective will of holders back into the cost of trading the asset.

  THE FOLD. A "fold" is one full governance cycle. Holders express a preference over the pool's
  fee tier — 0.05% / 0.30% / 1.00% — not by signing a public, bribeable, screenshot-able vote, but
  through an encrypted secret ballot run off-chain on the Enclave E3 / CRISP stack. Ballots are
  homomorphically tallied under FHE, the additive tally is proven correct with a RISC Zero ZK
  proof, and only the *plaintext result* is unfolded onto the chain. Nobody — not a whale, not a
  briber, not the deployer — can observe how any single holder voted, which is what makes the
  mechanism coercion-resistant: you cannot be paid for, or punished for, a vote no one can see.

  WHY GOVERN THE FEE AND NOT THE PRICE. AMM pricing is multiplicative (x*y=k) and hostile to FHE;
  an N-option fee ballot is pure additive aggregation, the one thing ZK-over-FHE does cheaply
  today. Interfold therefore governs the single parameter that is both economically meaningful and
  cryptographically tractable — the fee — and leaves swap math untouched. Each finalized fold is
  read by the pool's hook and applied as the live fee on the very next swap. The token contract
  itself stays deliberately inert so that the trust surface is the *pool*, never the asset.

  SUPPLY. A fixed 100,000 $FOLD, minted once, in full, to the deployer at genesis, to be folded
  entirely into pool liquidity. There is no inflation, no team allocation logic, and no second
  mint path — the constructor is the only place tokens ever come into existence.

  Links:
    X / Twitter:  https://x.com/theInterfold
    Website:      https://www.theinterfold.com/
//////////////////////////////////////////////////////////////////////////////////////////////*/

/// @title Token
/// @notice Bare, generic ERC20 with a fixed 100,000-unit supply minted entirely to a recipient
///         (the deployer, for seeding LP). No taxes, no transfer hooks — all governance lives in
///         the pool's V4 hook, not the token. Name and symbol are constructor params so the same
///         contract serves any launch (defaults to Interfold / $FOLD).
contract Token is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 100_000 ether; // 100k supply, all to deployer for LP

    constructor(string memory name_, string memory symbol_, address recipient) ERC20(name_, symbol_) {
        _mint(recipient, TOTAL_SUPPLY);
    }
}
