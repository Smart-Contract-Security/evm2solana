// SPDX-License-Identifier: MIT

/// @title BasisLedger
/// @notice Per-token tranche bookkeeping used by `Treasury`. Append-only; `sold` flips on
///         a successful `executeSell`, the entry is never removed. Price-source-agnostic —
///         `gainBps` takes an ETH-per-token quote from the caller.
library BasisLedger {
    struct Tranche {
        address token;
        uint64 amount;     // token units held in this tranche
        uint64 ethSpent;   // ETH spent acquiring this tranche
        uint40 boughtAt;   // block.timestamp at acquisition
        bool    sold;       // true once executeSell consumed this tranche
    }

    /// @notice Append a new tranche to a per-token array. Amount + ethSpent must fit in 64 bits.
    function pushTranche(
        Tranche[] storage tranches,
        address token,
        uint64 amount,
        uint64 ethSpent
    ) internal returns (uint256 index) {
        index = tranches.length;
        tranches.push(Tranche({
            token: token,
            amount: amount,
            ethSpent: ethSpent,
            boughtAt: uint40(block.timestamp),
            sold: false
        }));
    }

    function markSold(Tranche storage t) internal {
        t.sold = true;
    }

    /// @notice Realised-gain measurement against a supplied ETH-per-token quote (1e18-scaled).
    ///         Used by view paths only; `Treasury.executeSell` computes the trustless variant
    ///         (realized gain on actual ETH received) inline against `ethSpent`.
    /// @return basis-points gain, or 0 if the tranche would be at or below cost.
    function gainBps(Tranche memory t, uint256 ethPerToken1e18) internal pure returns (uint256) {
        // ethValue = amount * ethPerToken1e18 / 1e18
        uint256 ethValue = (uint256(t.amount) * ethPerToken1e18) / 1e18;
        if (ethValue <= t.ethSpent) return 0;
        unchecked {
            // ethValue > t.ethSpent (checked above), so the subtraction can't underflow.
            return ((ethValue - t.ethSpent) * 10_000) / t.ethSpent;
        }
    }
}