// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHatCard} from "../card/IHatCard.sol";
import {IMatchOracle} from "../oracle/IMatchOracle.sol";
import {MatchTypes} from "../oracle/MatchTypes.sol";
import {ScoringTypes} from "./ScoringTypes.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";

/// @title ScoringEngine
/// @notice Stateless. Computes (lineup, stats, stage, user) → points,
/// exactly as defined in whitepaper §06.
///
///   raw(c, g)        = Σ_{s ∈ T(c)}  w_s · ρ_s · x_{s,g}
///   P(c, g, u)       = max(0, raw) · μ_rarity(r(c)) · μ_stake(u)
///   bestGame(c, u)   = max_{g ∈ G}  P(c, g, u)
///   S_stage(u)       = Σ_{c ∈ XI(u)} bestGame(c, u)
///
/// All arithmetic is 1e6-scaled (`SCALE`) integer fixed-point. The final
/// returned points value is normalised back down by SCALE so callers get
/// raw integer points.
///
/// This contract holds NO storage. Settlement (writing per-user stage
/// allowances into PrizeVault) is owner-triggered: the operator runs the
/// scoring off-chain, calls `previewStage` to verify on chain, and then
/// pushes allowances into PrizeVault.setStageAllowance. The on-chain
/// `previewLineup` exists so any caller can independently verify a
/// reported score against settled stats.
contract ScoringEngine {
    IProtocolRegistry public immutable registry;

    constructor(IProtocolRegistry _registry) {
        registry = _registry;
    }

    /// @notice Preview the score for one card across one match.
    /// Returns 0 if the match isn't SETTLED yet.
    function previewCardMatch(uint256 tokenId, uint256 matchId, uint32 stakeMultiplierScaled)
        external
        view
        returns (uint256 points)
    {
        IMatchOracle oracle = IMatchOracle(registry.matchOracle());
        if (oracle.phaseOf(matchId) != MatchTypes.Phase.SETTLED) return 0;

        IHatCard card = IHatCard(registry.hatCard());
        IHatCard.Card memory c = card.getCard(tokenId);

        // The card's player must have been on the team-sheet for that match.
        // We don't enforce that here — callers should check via
        // oracle.playersInMatch(matchId). Stats not posted for the player
        // are zero, which yields raw=0 and points=0.

        int256 raw = _rawFor(c, matchId, oracle);
        if (raw < 0) return 0;

        // `raw` is already SCALE-multiplied (weights are 1e6-scaled).
        // Apply two more multipliers (rarity, stake) each themselves
        // SCALE-multiplied. The total accumulated scaling is SCALE^3 over
        // an integer-meaningful base of 1; divide by SCALE^3 to return
        // integer points (matches the whitepaper's "+18", "+14" examples).
        uint256 pos  = uint256(raw);
        uint256 mulR = ScoringTypes.rarityMultiplier(uint8(c.rarity));
        // (pos · mulR · stake) / SCALE^3
        // Done in two steps with intermediate /SCALE to avoid overflow.
        uint256 step = (pos * mulR) / ScoringTypes.SCALE;             // SCALE^1
        step         = (step * stakeMultiplierScaled) / ScoringTypes.SCALE;  // SCALE^0
        return step / ScoringTypes.SCALE;                              // raw integer points
    }

    /// @notice Sum-of-best-game over a lineup, for a stage's match window G.
    function previewLineup(
        uint256[] calldata lineup,
        uint256[] calldata matchIds,
        uint32   stakeMultiplierScaled
    ) external view returns (uint256 total) {
        for (uint256 i = 0; i < lineup.length; ++i) {
            uint256 best = 0;
            for (uint256 j = 0; j < matchIds.length; ++j) {
                uint256 p = this.previewCardMatch(lineup[i], matchIds[j], stakeMultiplierScaled);
                if (p > best) best = p;
            }
            total += best;
        }
    }

    // ─── internals ───────────────────────────────────────────────────────

    /// @dev raw(c, g) = Σ_{s ∈ T(c)} w_s · ρ_s · x_{s,g}.
    /// Returns the SCALE-applied signed integer (caller floors at zero).
    function _rawFor(IHatCard.Card memory c, uint256 matchId, IMatchOracle oracle)
        internal
        view
        returns (int256 raw)
    {
        uint32[18] memory w = ScoringTypes.statWeights();
        int8[18]   memory p = ScoringTypes.statPolarities();

        raw += _contribution(c.trait0.statId, c.playerId, matchId, oracle, w, p);
        raw += _contribution(c.trait1.statId, c.playerId, matchId, oracle, w, p);
        raw += _contribution(c.trait2.statId, c.playerId, matchId, oracle, w, p);
    }

    function _contribution(
        uint8 statId,
        uint16 playerId,
        uint256 matchId,
        IMatchOracle oracle,
        uint32[18] memory w,
        int8[18]   memory p
    ) internal view returns (int256) {
        uint32 x = oracle.statOf(matchId, playerId, MatchTypes.Stat(statId));
        // w[i] is SCALE-multiplied; multiplying by an integer x keeps the
        // result SCALE-multiplied without further normalisation here.
        int256 weighted = int256(uint256(w[statId])) * int256(uint256(x));
        return p[statId] >= 0 ? weighted : -weighted;
    }
}
