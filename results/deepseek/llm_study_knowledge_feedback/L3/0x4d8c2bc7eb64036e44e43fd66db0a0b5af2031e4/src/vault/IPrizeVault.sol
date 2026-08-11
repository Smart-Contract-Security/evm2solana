// SPDX-License-Identifier: MIT

import 'solana';

/// @title IPrizeVault
/// @notice Holds prize-pool inflows + per-stage emission budgets. Pays the
/// final ranking when the protocol reaches SETTLED.
interface IPrizeVault {
    /// @notice Hook calls this with the prize share of the swap-fee split.
    /// The currency is $HAT (the hook always denominates fees in HAT).
    function receivePrizeShare(uint64 hatAmount) external;

    /// @notice Per-stage emission claim — pulled by a user once the stage
    /// settles and the ScoringEngine has determined their score share.
    function claimEmission(address to, uint64 amount) external;

    function prizePoolBalance() external view returns (uint64);
    function stageEmissionRemaining(uint64 stageId) external view returns (uint64);
}