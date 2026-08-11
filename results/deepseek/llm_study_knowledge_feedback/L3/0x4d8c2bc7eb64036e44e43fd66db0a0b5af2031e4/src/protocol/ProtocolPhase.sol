// SPDX-License-Identifier: MIT

/// @title ProtocolPhase
/// @notice One-way state machine for the HAT-TRICK protocol, per whitepaper §09.
///
/// Transitions are gated by time and the oracle; there is no path back to an
/// earlier phase. Each module reads the current phase from ProtocolRegistry
/// to gate phase-bound operations (PackSale only in PRESALE/WHITELIST, $HAT
/// minting only after TGE, etc.).
library ProtocolPhase {
    enum Phase {
        PRESALE,    // 0 — packs on sale, cards mintable, no token, no scoring
        WHITELIST,  // 1 — engage + amplify campaigns lock early access
        TGE,        // 2 — pack sales close, $HAT mints, v4 pool + hook go live
        LIVE,       // 3 — tournament running, oracle settles, stages pay out
        FULL_TIME,  // 4 — final match settled, emission schedule exhausted
        SETTLED     // 5 — prize pool paid by final ranking, protocol read-only
    }

    /// @notice Forward-only transition guard. Reverts if `to <= from`.
    function _requireForward(Phase from, Phase to) internal pure {
        require(uint8(to) > uint8(from), "phase: not forward");
    }
}