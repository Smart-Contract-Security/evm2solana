// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title BasisLedger
/// @notice Per-token tranche bookkeeping used by `Treasury`. Append-only; `sold` flips on
///         a successful `executeSell`, the entry is never removed. Price-source-agnostic —
///         `gainBps` takes an ETH-per-token quote from the caller.
library BasisLedger {
    struct Tranche {
        address token;
        uint128 amount;     // token units held in this tranche
        uint128 ethSpent;   // ETH spent acquiring this tranche
        uint40  boughtAt;   // block.timestamp at acquisition
        bool    sold;       // true once executeSell consumed this tranche
    }

    /// @notice Append a new tranche to a per-token array. Amount + ethSpent must fit in 128 bits.
    function pushTranche(
        Tranche[] storage tranches,
        address token,
        uint256 amount,
        uint256 ethSpent
    ) internal returns (uint256 index) {
        if (amount > type(uint128).max) {
            revert("AmountOverflow");
        }
        if (ethSpent > type(uint128).max) {
            revert("EthSpentOverflow");
        }
        index = tranches.length;
        tranches.push(Tranche({
            token: token,
            amount: uint128(amount),
            ethSpent: uint128(ethSpent),
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
        // We multiply uint128 * uint256 — the intermediate cannot overflow because
        // amount <= 2^128 - 1 and ethPerToken1e18 < 2^128 in any realistic scenario
        // (1e18 wei per token = ~$3000/token at $3000/ETH); 2^128 ~= 3.4e38 which is
        // ~3.4e20 ETH per token, well above any sane value.
        uint256 ethValue = (uint256(t.amount) * ethPerToken1e18) / 1e18;
        if (ethValue <= t.ethSpent) return 0;
        unchecked {
            // ethValue > t.ethSpent (checked above), so the subtraction can't underflow.
            return ((ethValue - t.ethSpent) * 10_000) / t.ethSpent;
        }
    }
}