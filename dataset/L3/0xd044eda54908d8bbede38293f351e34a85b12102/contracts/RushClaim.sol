// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20}             from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}          from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}            from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard}    from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGateCoin}          from "./interfaces/IGateCoin.sol";
import {IRushBurn}          from "./interfaces/IRushBurn.sol";

/**
 * @title RushClaim — phase-3 claim controller (no-trust S resolution).
 *
 *  Each wallet has:
 *    S       : spin entitlement, computed on-chain from
 *              `gateCoin.spinReward(user)`. Resolved lazily at first
 *              claim — no external party can inject a value.
 *    K_nft   : 1.0 / 2.0 / 3.5  (from gateCoin.balanceOf)
 *    K_burn  : 1.0 … 2.0        (from RushBurn.kBurnScaled / 1e4)
 *    W       : S × K_nft × K_burn   ← ceiling
 *
 *  Tokens drip at rate r(t) = (W − claimed) / max(remainingPhase, τ)
 *  with τ = TAU_SECONDS = 36h. This guarantees:
 *    - No wallet can drain in less than τ.
 *    - At phase end, anything unclaimed is forfeit (sent to 0xdead by
 *      the public `closePhase()`).
 *
 *  Pull model: user calls `claim()` and gets `claimable()` worth.
 *  We maintain `lastClaimAt` per wallet to integrate the rate over time.
 *
 *  Treasury: 80M RUSH must be transferred into this contract before
 *  `openPhase()` is called.
 *
 *  == Why there is no `creditSpin` / no `minter` ==
 *  An earlier design had `creditSpin(user, amount)` called by GateCoin
 *  on first mint, gated by an owner-settable `minter` address. This
 *  trusted the caller's `amount` and allowed the owner to inflate spin
 *  credits between deploy and `openPhase` by pointing `minter` at an EOA.
 *
 *  Fix: S is resolved here, not received. The contract calls
 *  `gateCoin.spinReward(user)` directly — `spinReward` is `pure` and
 *  derives from the SPIN_SEED baked into GateCoin's immutable bytecode,
 *  so no privileged caller can change the answer. The materialization
 *  also requires `gateCoin.balanceOf(user) > 0`, preserving the
 *  "no mint, no spin" invariant.
 */
contract RushClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============================ errors ============================ */
    error PhaseClosed();
    error PhaseAlreadyOpen();
    error PhaseNotEnded();
    error PhaseTooShort();
    error CannotRescueRush();
    error NothingToClaim();
    error NotEOA();

    /* ============================ constants ============================ */
    uint256 public constant TAU_SECONDS         = 36 hours;
    uint256 public constant E4                  = 10_000;
    uint256 public constant MIN_CLAIM_DURATION  = 96 hours;
    address public constant DEAD                = 0x000000000000000000000000000000000000dEaD;

    /* NFT K table, scaled to 1e4 */
    uint256 public constant K_NFT_1_E4 = 10_000; // ×1.0
    uint256 public constant K_NFT_2_E4 = 20_000; // ×2.0
    uint256 public constant K_NFT_3_E4 = 35_000; // ×3.5

    /* ============================ wires ============================ */
    IERC20     public immutable rush;
    IGateCoin  public immutable gateCoin;
    IRushBurn  public immutable burnContract;

    /* ============================ phase state ============================ */
    bool    public phaseOpen;
    uint64  public phaseStart;
    uint64  public phaseEnd;       // owner sets a hard end (e.g. start + 96h)

    /* ============================ per-wallet ============================ */
    struct ClaimRecord {
        uint128 sCredited;        // spin entitlement, materialized on first claim
        uint128 claimed;          // RUSH already claimed
        uint64  lastClaimAt;      // last withdraw timestamp (or phaseStart)
    }
    mapping(address => ClaimRecord) public records;

    /* aggregates */
    uint256 public totalCredited;
    uint256 public totalClaimed;

    /* ============================ events ============================ */
    event PhaseOpened(uint64 start, uint64 end);
    event PhaseClosedEvent(uint64 timestamp, uint256 remainder);

    /// Emitted the first time a wallet's spin entitlement is materialized
    /// from `gateCoin.spinReward(user)` into storage. Emitted at most once
    /// per wallet. Surface is the same as the old `creditSpin` event so
    /// downstream indexers don't break.
    event SpinCredited(address indexed user, uint256 amount, uint256 totalCredited);

    /// Per-claim payout. `wRemaining` lets the indexer / frontend show progress.
    event Claimed(
        address indexed user,
        uint256 amount,
        uint256 cumulativeClaimed,
        uint256 wRemaining,
        uint256 kTotalE4
    );

    /* ============================ ctor / admin ============================ */
    constructor(address _rush, address _gateCoin, address _burn) Ownable(msg.sender) {
        rush         = IERC20(_rush);
        gateCoin     = IGateCoin(_gateCoin);
        burnContract = IRushBurn(_burn);
    }

    /// Owner opens the claim window. `endTimestamp` must be at least
    /// `MIN_CLAIM_DURATION` (96h) in the future so owner cannot grief the
    /// window down to a few seconds.
    function openPhase(uint64 endTimestamp) external onlyOwner {
        if (phaseOpen) revert PhaseAlreadyOpen();
        if (endTimestamp < block.timestamp + MIN_CLAIM_DURATION) revert PhaseTooShort();
        phaseOpen   = true;
        phaseStart  = uint64(block.timestamp);
        phaseEnd    = endTimestamp;
        emit PhaseOpened(phaseStart, endTimestamp);
    }

    /// PUBLIC, anyone can call after `phaseEnd`. Leftover RUSH is sent to
    /// `0xdead` — burned, NOT recoverable by the owner. This makes the
    /// claim treasury fully trustless: the only paths for RUSH to leave the
    /// contract are user-initiated `claim()` calls (gated by W/τ math) and
    /// the post-phase burn here. Owner has no token destination control.
    function closePhase() external {
        if (!phaseOpen)                    revert PhaseClosed();
        if (block.timestamp < phaseEnd)    revert PhaseNotEnded();
        phaseOpen = false;
        uint256 bal = rush.balanceOf(address(this));
        if (bal > 0) rush.safeTransfer(DEAD, bal);
        emit PhaseClosedEvent(uint64(block.timestamp), bal);
    }

    /* ============================ claim ============================ */
    function claim() external nonReentrant {
        if (msg.sender != tx.origin)         revert NotEOA();
        if (!phaseOpen)                       revert PhaseClosed();
        if (block.timestamp >= phaseEnd)      revert PhaseClosed();  // hard cutoff

        // Idempotent: materializes S from gateCoin.spinReward at most once
        // per wallet. Safe to call every claim — no-op after first.
        _materializeS(msg.sender);

        uint256 amount = claimable(msg.sender);
        if (amount == 0) revert NothingToClaim();

        ClaimRecord storage rec = records[msg.sender];
        rec.claimed     += uint128(amount);
        rec.lastClaimAt  = uint64(block.timestamp);
        totalClaimed    += amount;

        rush.safeTransfer(msg.sender, amount);

        (uint256 w, uint256 kTotal) = _wAndK(msg.sender);
        uint256 remaining = w > rec.claimed ? w - rec.claimed : 0;
        emit Claimed(msg.sender, amount, rec.claimed, remaining, kTotal);
    }

    /* ============================ views ============================ */
    /// Available-to-claim right now for `user`. Min(W − claimed, rate · Δt).
    /// Returns 0 once `phaseEnd` is reached so the frontend stops dripping
    /// the counter — actually claiming reverts at the same point.
    function claimable(address user) public view returns (uint256) {
        if (!phaseOpen)                   return 0;
        if (block.timestamp >= phaseEnd)  return 0;

        ClaimRecord memory rec = records[user];
        // Preview S without writing — uses storage if already materialized,
        // otherwise computes from gateCoin.spinReward + balance gate.
        (uint256 w, ) = _wAndKPreview(user);
        if (w <= rec.claimed) return 0;

        uint256 since = block.timestamp - (rec.lastClaimAt == 0 ? phaseStart : rec.lastClaimAt);
        // τ-cap: max rate = W / TAU. So available = (W * since) / TAU − offset
        uint256 byRate = (w * since) / TAU_SECONDS;
        uint256 hardRemaining = w - rec.claimed;
        return byRate < hardRemaining ? byRate : hardRemaining;
    }

    /// Returns (W, K_total scaled to 1e8) using either stored or
    /// previewed S. Useful for the frontend "preview" before first claim.
    function previewW(address user) external view returns (uint256 w, uint256 kE8) {
        return _wAndKPreview(user);
    }

    /* ============================ internals ============================ */

    /// Lazy materialization. On first call for `user`, queries the
    /// pure on-chain `spinReward` and writes it to storage IF the wallet
    /// has actually minted at least one Gate Coin. Idempotent.
    function _materializeS(address user) internal {
        ClaimRecord storage rec = records[user];
        if (rec.sCredited != 0) return;                       // already done
        if (gateCoin.balanceOf(user) == 0) return;            // "no mint, no spin"
        uint256 s = gateCoin.spinReward(user);
        if (s == 0) return;
        rec.sCredited = uint128(s);
        totalCredited += s;
        emit SpinCredited(user, s, totalCredited);
    }

    /// Internal helper that uses already-materialized S in storage.
    /// Used inside `claim()` AFTER `_materializeS` writes the value, so
    /// the read is always up to date.
    function _wAndK(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 s = records[user].sCredited;
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(gateCoin.balanceOf(user));
        uint256 kBrnE4 = burnContract.kBurnScaled(user);

        // k_total in 1e8: (kNft × kBurn) — both are 1e4 each, so product is 1e8.
        kE8 = kNftE4 * kBrnE4;
        w   = (s * kE8) / 1e8;
    }

    /// View-only preview of (W, K_total). Uses storage S if it has been
    /// materialized; otherwise derives it on the fly from `gateCoin.spinReward`
    /// behind the same balanceOf > 0 gate that `_materializeS` enforces.
    /// Pure view — never writes.
    function _wAndKPreview(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 nftCount = gateCoin.balanceOf(user);
        if (nftCount == 0) return (0, 0);

        uint256 s = records[user].sCredited;
        if (s == 0) s = gateCoin.spinReward(user);
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(nftCount);
        uint256 kBrnE4 = burnContract.kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w   = (s * kE8) / 1e8;
    }

    function _kNftE4(uint256 nftCount) internal pure returns (uint256) {
        if (nftCount >= 3) return K_NFT_3_E4;
        if (nftCount == 2) return K_NFT_2_E4;
        if (nftCount == 1) return K_NFT_1_E4;
        return E4;   // 1.0 floor — but with 0 NFTs, S is also 0 (gated above)
    }

    /* ============================ rescue ============================ */
    /// Recover stray ERC-20 tokens that were sent here by mistake.
    /// RUSH is explicitly blocked — that's the claim treasury and the only
    /// legitimate exit is `closePhase` (gated on `phaseEnd`).
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        if (token == address(rush)) revert CannotRescueRush();
        IERC20(token).safeTransfer(owner(), amount);
    }
}
