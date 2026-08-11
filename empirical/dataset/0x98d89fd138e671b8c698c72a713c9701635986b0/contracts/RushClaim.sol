// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20}             from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}          from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}            from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard}    from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC721}            from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IRushBurn}          from "./interfaces/IRushBurn.sol";

/**
 * @title RushClaim — phase-3 claim controller.
 *
 *  Each wallet has:
 *    S       : spin entitlement (credited by GateCoin on first mint)
 *    K_nft   : 1.0 / 2.0 / 3.5  (from GateCoin.balanceOf)
 *    K_burn  : 1.0 … 2.0        (from RushBurn.kBurnScaled / 1e4)
 *    W       : S × K_nft × K_burn   ← ceiling
 *
 *  Tokens drip at rate r(t) = (W − claimed) / max(remainingPhase, τ)
 *  with τ = TAU_SECONDS = 36h. This guarantees:
 *    - No wallet can drain in less than τ.
 *    - At phase end, anything unclaimed is forfeit (or owner-swept).
 *
 *  Pull model: user calls `claim()` and gets `claimable()` worth.
 *  We maintain `lastClaimAt` per wallet to integrate the rate over time.
 *
 *  Treasury: 80M RUSH must be transferred into this contract before
 *  `openPhase()` is called.
 */
contract RushClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============================ errors ============================ */
    error NotMinter();
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
    IERC721    public immutable gateCoin;
    IRushBurn  public immutable burnContract;
    address    public minter;      // = GateCoin (it is the only thing that calls creditSpin)

    /* ============================ phase state ============================ */
    bool    public phaseOpen;
    uint64  public phaseStart;
    uint64  public phaseEnd;       // owner sets a hard end (e.g. start + 96h)

    /* ============================ per-wallet ============================ */
    struct ClaimRecord {
        uint128 sCredited;        // spin entitlement, set on first mint
        uint128 claimed;          // RUSH already claimed
        uint64  lastClaimAt;      // last withdraw timestamp (or phaseStart)
    }
    mapping(address => ClaimRecord) public records;

    /* aggregates */
    uint256 public totalCredited;
    uint256 public totalClaimed;

    /* ============================ events ============================ */
    event MinterSet(address indexed newMinter);
    event PhaseOpened(uint64 start, uint64 end);
    event PhaseClosedEvent(uint64 timestamp, uint256 remainder);

    /// Called by GateCoin on a wallet's first mint.
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
        gateCoin     = IERC721(_gateCoin);
        burnContract = IRushBurn(_burn);
    }

    /// Wire the GateCoin contract. Locks once phase opens, so a future
    /// owner-compromise cannot redirect spin credits to a malicious minter.
    function setMinter(address m) external onlyOwner {
        if (phaseOpen) revert PhaseAlreadyOpen();
        minter = m;
        emit MinterSet(m);
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

    /* ============================ credit (from GateCoin) ============================ */
    function creditSpin(address user, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        ClaimRecord storage rec = records[user];
        // Idempotency: only credit if not already credited.
        if (rec.sCredited == 0 && amount > 0) {
            rec.sCredited = uint128(amount);
            totalCredited += amount;
            emit SpinCredited(user, amount, totalCredited);
        }
    }

    /* ============================ claim ============================ */
    function claim() external nonReentrant {
        if (msg.sender != tx.origin)         revert NotEOA();
        if (!phaseOpen)                       revert PhaseClosed();
        if (block.timestamp >= phaseEnd)      revert PhaseClosed();  // hard cutoff

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
        (uint256 w, ) = _wAndK(user);
        if (w <= rec.claimed) return 0;

        uint256 since = block.timestamp - (rec.lastClaimAt == 0 ? phaseStart : rec.lastClaimAt);
        // τ-cap: max rate = W / TAU. So available = (W * since) / TAU − offset
        uint256 byRate = (w * since) / TAU_SECONDS;
        uint256 hardRemaining = w - rec.claimed;
        return byRate < hardRemaining ? byRate : hardRemaining;
    }

    /// Returns (W, K_total scaled to 1e8). Useful for the frontend "preview".
    function previewW(address user) external view returns (uint256 w, uint256 kE8) {
        return _wAndK(user);
    }

    function _wAndK(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 s = records[user].sCredited;
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(gateCoin.balanceOf(user));
        uint256 kBrnE4 = burnContract.kBurnScaled(user);

        // k_total in 1e8: (kNft × kBurn) / 1e0 — both are 1e4 each, so product is 1e8.
        kE8 = kNftE4 * kBrnE4;
        w   = (s * kE8) / 1e8;
    }

    function _kNftE4(uint256 nftCount) internal pure returns (uint256) {
        if (nftCount >= 3) return K_NFT_3_E4;
        if (nftCount == 2) return K_NFT_2_E4;
        if (nftCount == 1) return K_NFT_1_E4;
        return E4;   // 1.0 floor — but with 0 NFTs, S is also 0 (no mint = no spin)
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
