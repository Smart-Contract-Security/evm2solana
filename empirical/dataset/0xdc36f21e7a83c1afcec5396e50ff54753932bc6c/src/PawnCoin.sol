// SPDX-License-Identifier: MIT
// ════════════════════════════════════════════════════════════════
//   Pawn-5D · PAWN
//   Website  : https://pawn5d.com
//   App      : https://app.pawn5d.com
//   Twitter  : https://x.com/Pawn_ERC5D
// ════════════════════════════════════════════════════════════════
// ██████╗░░█████╗░░██╗░░░░░░░██╗███╗░░██╗
// ██╔══██╗██╔══██╗░██║░░██╗░░██║████╗░██║
// ██████╔╝███████║░╚██╗████╗██╔╝██╔██╗██║
// ██╔═══╝░██╔══██║░░████╔═████║░██║╚████║
// ██║░░░░░██║░░██║░░╚██╔╝░╚██╔╝░██║░╚███║
// ╚═╝░░░░░╚═╝░░╚═╝░░░╚═╝░░░╚═╝░░╚═╝░░╚══╝
pragma solidity ^0.8.24;

import {PawnToken} from "./PawnToken.sol";

/**
 * PawnCoin — deployable token contract.
 * Thin wrapper over PawnToken to differentiate bytecode metadata
 * from the abandoned mirrored deployment. Full behaviour inherits
 * from PawnToken (ERC-5D, NFT-404, rotating tier rewards, etc.).
 */
contract PawnCoin is PawnToken {
    constructor(address marketingWallet_, address treasury_, address router_)
        PawnToken(marketingWallet_, treasury_, router_)
    {}
}
