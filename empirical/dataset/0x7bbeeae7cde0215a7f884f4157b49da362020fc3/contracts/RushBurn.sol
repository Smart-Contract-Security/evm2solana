// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20}            from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}         from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}           from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard}   from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable}          from "@openzeppelin/contracts/utils/Pausable.sol";
import {IUniswapV2Pair}    from "./interfaces/IUniswapV2Pair.sol";
import {IRushBurn}         from "./interfaces/IRushBurn.sol";

/**
 * @title RushBurn — phase-2 burn controller.
 *
 *  ALWAYS-ON: deploy-time live. Natural gating ("no pair → can't read spot
 *  price → revert; no tokens → can't approve burn") keeps users out until
 *  P2 actually starts. The site-side toggle (see `site-react/src/config.js`)
 *  is purely cosmetic.
 *
 *  Two burn modes, owner-switchable WITHOUT redeploy:
 *
 *  ─── BurnMode.SpotPriced (default) ──────────────────────────────────────
 *    Reads pair reserves to value the user's burn in ETH terms.
 *    ethValue = amount × rWeth / rRush
 *
 *  ─── BurnMode.FlatRate (fallback) ───────────────────────────────────────
 *    Uses a fixed conversion `flatRateRushAtCap` (RUSH per 0.05 ETH-equiv).
 *    ethValue = amount × B_MAX_ETH / flatRateRushAtCap
 *    Use this if the AMM gets manipulated or the pair address goes weird.
 *
 *  Both modes feed the same K_burn formula:
 *    K_burn = clamp(1 + sqrt(ethValueAccum / B_MAX_ETH), 1.0, 2.0)
 *
 *  Anti-flash-loan:  `tx.origin == msg.sender`.
 *  Emergency stop:    OZ Pausable — owner can `pause()` / `unpause()`.
 *  Pair lock:         owner can call `freezePair()` one-way to seal the
 *                     pair address before launch.
 */
contract RushBurn is IRushBurn, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ============================== modes ============================== */
    enum BurnMode { SpotPriced, FlatRate }

    /* ============================== errors ============================== */
    error NotEOA();
    error ZeroAmount();
    error CapReached();
    error PoolEmpty();
    error PoolNotSet();
    error PairAlreadyFrozen();
    error ZeroFlatRate();

    /* ============================== constants ============================== */
    address public constant DEAD       = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant B_MAX_ETH  = 0.05 ether;
    uint256 public constant K_MIN_E4   = 10_000;   // ×1.0
    uint256 public constant K_MAX_E4   = 20_000;   // ×2.0

    /* ============================== wires & state ============================== */
    IERC20            public immutable rush;
    IUniswapV2Pair    public pair;             // settable until frozen
    bool              public pairFrozen;       // one-way lock
    BurnMode          public mode;             // default SpotPriced
    uint256           public flatRateRushAtCap; // RUSH that = 0.05 ETH in FlatRate

    /* ============================== per-wallet ============================== */
    struct BurnRecord {
        uint128 totalRushBurned;
        uint128 totalEthValue;   // capped at B_MAX_ETH
        uint64  lastTimestamp;
        uint64  burnCount;
    }
    mapping(address => BurnRecord) public records;

    /* ============================== aggregates ============================== */
    uint256 public globalRushBurned;
    uint256 public globalEthValueAccum;
    uint64  public globalBurnCount;

    /* ============================== events ============================== */
    event PoolSet(address indexed pair);
    event PairFrozen();
    event ModeSet(BurnMode mode);
    event FlatRateSet(uint256 rushAtCap);

    event Burned(
        address indexed user,
        uint256 rushAmount,
        uint256 ethValue,
        uint256 ethValueAccum,
        uint256 kBurnE4Old,
        uint256 kBurnE4New,
        BurnMode mode
    );
    event BurnCapReached(address indexed user, uint256 ethValueAccum);

    /// Emitted ONLY in SpotPriced mode — frontend can plot the price feed.
    event SpotReadAtBurn(
        address indexed user,
        uint112 reserveRush,
        uint112 reserveWeth
    );
    /// Emitted ONLY in FlatRate mode — frontend can show "admin-set rate" badge.
    event FlatRateBurn(
        address indexed user,
        uint256 rushAmount,
        uint256 ethValueEquivalent
    );

    /* ============================== ctor / admin ============================== */
    /**
     * @param rushToken           $RUSH ERC-20 address
     * @param _flatRateRushAtCap  default fallback rate; 0 → uses 750_000e18
     *                            (matches seed price 1 ETH = 15M RUSH)
     */
    constructor(address rushToken, uint256 _flatRateRushAtCap) Ownable(msg.sender) {
        rush = IERC20(rushToken);
        flatRateRushAtCap = _flatRateRushAtCap == 0 ? 750_000e18 : _flatRateRushAtCap;
        emit FlatRateSet(flatRateRushAtCap);
        emit ModeSet(BurnMode.SpotPriced);
    }

    /// Set / change the Uniswap pair. Locks once `freezePair()` is called.
    function setPair(address _pair) external onlyOwner {
        if (pairFrozen) revert PairAlreadyFrozen();
        pair = IUniswapV2Pair(_pair);
        emit PoolSet(_pair);
    }

    /// One-way: seal the pair address. After this, only `setMode` / `setFlatRate`
    /// remain as live admin levers — `setPair` is permanently locked.
    function freezePair() external onlyOwner {
        if (address(pair) == address(0)) revert PoolNotSet();
        pairFrozen = true;
        emit PairFrozen();
    }

    /// Switch burn mode (instant). Used as a fallback if AMM spot becomes
    /// unreliable. Stays callable for the contract's lifetime.
    function setMode(BurnMode m) external onlyOwner {
        mode = m;
        emit ModeSet(m);
    }

    /// Adjust the FlatRate cap denominator. e.g. 750_000e18 means
    /// "750k RUSH = max K". Setter stays live for the contract's lifetime.
    function setFlatRateRushAtCap(uint256 r) external onlyOwner {
        if (r == 0) revert ZeroFlatRate();
        flatRateRushAtCap = r;
        emit FlatRateSet(r);
    }

    /// OZ Pausable surface — emergency stop.
    function pause()   external onlyOwner { _pause();   }
    function unpause() external onlyOwner { _unpause(); }

    /* ============================== burn ============================== */
    function burn(uint256 amount) external whenNotPaused nonReentrant {
        // anti-flash-loan
        if (msg.sender != tx.origin) revert NotEOA();
        if (amount == 0)             revert ZeroAmount();

        // pull tokens from caller (requires prior approve)
        rush.safeTransferFrom(msg.sender, address(this), amount);

        // ----- mode-dependent ETH-value computation -----
        uint256 ethValueRaw = _ethValue(amount, msg.sender);

        // ----- apply per-wallet cap -----
        BurnRecord storage rec = records[msg.sender];
        uint256 prevEth    = rec.totalEthValue;
        uint256 newEth     = prevEth + ethValueRaw;
        uint256 ethCounted = ethValueRaw;
        if (newEth > B_MAX_ETH) {
            ethCounted = B_MAX_ETH - prevEth;
            newEth     = B_MAX_ETH;
            if (ethCounted == 0) revert CapReached();
        }

        // ----- K_burn -----
        uint256 kOld = _kFromEth(prevEth);
        uint256 kNew = _kFromEth(newEth);

        rec.totalRushBurned += uint128(amount);
        rec.totalEthValue    = uint128(newEth);
        rec.lastTimestamp    = uint64(block.timestamp);
        rec.burnCount        += 1;

        globalRushBurned    += amount;
        globalEthValueAccum += ethCounted;
        globalBurnCount     += 1;

        // ----- forward to dead -----
        rush.safeTransfer(DEAD, amount);

        emit Burned(msg.sender, amount, ethCounted, newEth, kOld, kNew, mode);
        if (newEth == B_MAX_ETH && prevEth < B_MAX_ETH) {
            emit BurnCapReached(msg.sender, newEth);
        }
    }

    function _ethValue(uint256 amount, address user) internal returns (uint256) {
        if (mode == BurnMode.SpotPriced) {
            if (address(pair) == address(0)) revert PoolNotSet();
            (uint112 r0, uint112 r1,) = pair.getReserves();
            address token0 = pair.token0();
            (uint112 rRush, uint112 rWeth) = token0 == address(rush) ? (r0, r1) : (r1, r0);
            if (rRush == 0 || rWeth == 0) revert PoolEmpty();
            emit SpotReadAtBurn(user, rRush, rWeth);
            return (amount * uint256(rWeth)) / uint256(rRush);
        } else {
            uint256 v = (amount * B_MAX_ETH) / flatRateRushAtCap;
            emit FlatRateBurn(user, amount, v);
            return v;
        }
    }

    /* ============================== views ============================== */
    function kBurnScaled(address user) external view returns (uint256) {
        return _kFromEth(records[user].totalEthValue);
    }

    function _kFromEth(uint256 ethWei) internal pure returns (uint256) {
        if (ethWei == 0)         return K_MIN_E4;
        if (ethWei >= B_MAX_ETH) return K_MAX_E4;
        // K = 1 + sqrt(eth / B_MAX) → scaled: kE4 = 1e4 + sqrt(eth * 1e8 / B_MAX)
        uint256 inner = (ethWei * 1e8) / B_MAX_ETH;
        return K_MIN_E4 + _sqrt(inner);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
