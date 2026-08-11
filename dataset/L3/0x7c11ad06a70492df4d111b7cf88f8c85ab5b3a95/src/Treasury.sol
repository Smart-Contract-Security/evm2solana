// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {ITFLOBuyback} from "./interfaces/ITFLOBuyback.sol";
import {BasisLedger} from "./BasisLedger.sol";

/// @title Treasury
/// @notice Holds ETH from fee harvesting; deploys it into a team-curated eligible-token universe
///         via deterministic round-robin buys; tracks per-token tranches; routes sale proceeds
///         to the TFLO buyback. v1 design: owner-only `triggerBuy` / `executeSell` with caller-
///         supplied `minOut` for slippage protection (see ARCHITECTURE.md §1 centralization note).
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using BasisLedger for BasisLedger.Tranche[];

    // ── External refs (immutable) ──────────────────────────────────────────────────────────────
    ISwapRouter   public immutable SWAP_ROUTER;
    ITFLOBuyback  public immutable BUYBACK;

    // ── Upper bounds only (from ARCHITECTURE.md §3.1, §3.2) ────────────────────────────────────
    // No lower bound on buyThreshold / sellGainBps: the owner sets sensible values and is solely
    // responsible for them (v1 trusted-owner model, §9.16). A 0 sellGainBps disables the
    // realized-gain floor entirely (any sale, incl. a loss, passes) — this is the deliberate
    // emergency-exit lever, not an accident. Only the upper caps are enforced on-chain.
    uint256 public constant MAX_BUY_THRESHOLD = 10 ether;
    uint16  public constant MAX_SELL_GAIN_BPS = 5000;
    uint8   public constant MAX_ELIGIBLE_TOKENS = 50;
    uint8   public constant PER_BUY_CAP_MULTIPLIER = 2;

    // ── Storage (see ARCHITECTURE.md §5) ───────────────────────────────────────────────────────
    mapping(address => BasisLedger.Tranche[]) public _tranches;
    address[] public eligibleTokens;
    mapping(address => bool)  public isEligible;
    uint256 public nextBuyIndex;

    uint256 public buyThreshold;
    uint16  public sellGainBps;

    /// @notice Secondary caller authorized to invoke `triggerBuy` / `executeSell`.
    ///         Starts at address(0); owner sets via `setTrader`. The v2 TWAP-validating
    ///         trigger contract is installed here without transferring ownership.
    address public trader;

    // ── Events ─────────────────────────────────────────────────────────────────────────────────
    event Bought(address indexed winner, uint256 indexed idx, uint256 ethSpent, uint256 tokenOut);
    event Sold(
        address indexed token,
        uint256 indexed trancheIndex,
        uint256 amount,
        uint256 ethReceived,
        uint256 realizedGainBps
    );
    event EligibleAdded(address indexed token);
    event EligibleRemoved(address indexed token);
    event BuyThresholdSet(uint256 newValue);
    event SellGainBpsSet(uint16 newValue);
    event TraderSet(address indexed oldTrader, address indexed newTrader);

    // ── Errors ─────────────────────────────────────────────────────────────────────────────────
    error BuyThresholdOutOfBounds(uint256 value);
    error SellGainBpsOutOfBounds(uint16 value);
    error AlreadyEligible(address token);
    error NotEligible(address token);
    error EligibleListFull();
    error InsufficientTreasuryBalance(uint256 balance, uint256 threshold);
    error NoEligibleTokens();
    error TrancheOutOfRange(address token, uint256 trancheIndex);
    error TrancheAlreadySold();
    error RealizedGainBelowFloor(uint256 realized, uint256 floor);
    error NotOwnerOrTrader(address caller);

    /// @param swapRouter  SwapRouter — forwards operator-built Universal Router routes.
    /// @param buyback     TFLOBuyback — final hop on every sell.
    /// @param defaultBuyThreshold Initial buy threshold (must be within MIN/MAX).
    /// @param defaultSellGainBps  Initial sell-gain floor (must be within MIN/MAX).
    constructor(
        ISwapRouter swapRouter,
        ITFLOBuyback buyback,
        uint256 defaultBuyThreshold,
        uint16 defaultSellGainBps
    ) Ownable(msg.sender) {
        if (defaultBuyThreshold > MAX_BUY_THRESHOLD) {
            revert BuyThresholdOutOfBounds(defaultBuyThreshold);
        }
        if (defaultSellGainBps > MAX_SELL_GAIN_BPS) {
            revert SellGainBpsOutOfBounds(defaultSellGainBps);
        }

        SWAP_ROUTER = swapRouter;
        BUYBACK     = buyback;

        buyThreshold = defaultBuyThreshold;
        sellGainBps  = defaultSellGainBps;
    }

    receive() external payable {}

    // ── Owner config setters ───────────────────────────────────────────────────────────────────

    function setBuyThreshold(uint256 value) external onlyOwner {
        if (value > MAX_BUY_THRESHOLD) {
            revert BuyThresholdOutOfBounds(value);
        }
        buyThreshold = value;
        emit BuyThresholdSet(value);
    }

    function setSellGainBps(uint16 value) external onlyOwner {
        if (value > MAX_SELL_GAIN_BPS) {
            revert SellGainBpsOutOfBounds(value);
        }
        sellGainBps = value;
        emit SellGainBpsSet(value);
    }

    /// @notice Assign (or clear, with address(0)) the secondary caller permitted to invoke
    ///         `triggerBuy` / `executeSell`. Single-step; the owner is solely responsible
    ///         for vetting the new address (matches the project's single-step `Ownable` posture).
    function setTrader(address newTrader) external onlyOwner {
        address old = trader;
        trader = newTrader;
        emit TraderSet(old, newTrader);
    }

    /// @notice Add a token to the round-robin buy universe. How it is traded (which
    ///         pools / route) is decided off-chain per trade by the operator's router
    ///         and supplied as Universal Router calldata to `triggerBuy`/`executeSell`
    ///         — there is no on-chain pool descriptor (see ARCHITECTURE.md §5).
    function addEligibleToken(address token) external onlyOwner {
        if (eligibleTokens.length >= MAX_ELIGIBLE_TOKENS) revert EligibleListFull();
        if (isEligible[token]) revert AlreadyEligible(token);

        eligibleTokens.push(token);
        isEligible[token] = true;

        // One-time, never-decreased max approval to SwapRouter. Sells pull the tranche via
        // SwapRouter.transferFrom, so granting the allowance once here removes the per-sell
        // approval from executeSell. The allowance is never reduced (removeEligibleToken leaves
        // it intact) so retained tranches stay sellable forever — see §9.9.
        IERC20(token).forceApprove(address(SWAP_ROUTER), type(uint256).max);

        emit EligibleAdded(token);
    }

    function removeEligibleToken(address token) external onlyOwner {
        if (!isEligible[token]) revert NotEligible(token);

        // Swap-and-pop on eligibleTokens[]. nextBuyIndex is NEVER mutated.
        uint256 len = eligibleTokens.length;
        for (uint256 i = 0; i < len; ) {
            if (eligibleTokens[i] == token) {
                if (i != len - 1) {
                    eligibleTokens[i] = eligibleTokens[len - 1];
                }
                eligibleTokens.pop();
                break;
            }
            unchecked { ++i; }
        }

        isEligible[token] = false;
        // _tranches[token] intentionally retained so historical holdings stay sellable
        // forever (the off-chain router can still build a sell route) — see §9.9.

        emit EligibleRemoved(token);
    }

    // ── Owner-or-trader trade triggers (v1: caller-supplied minOut from off-chain quoter) ──────

    function _requireOwnerOrTrader() internal view {
        if (msg.sender != owner() && msg.sender != trader) revert NotOwnerOrTrader(msg.sender);
    }

    /// @param commands Universal Router command bytes for the ETH→winner route (operator-built).
    /// @param inputs   Per-command inputs. The route MUST output the winning token to this Treasury.
    /// @param minOut   Minimum winning-token amount; enforced by SwapRouter's balance-delta check.
    function triggerBuy(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOut
    ) external nonReentrant {
        _requireOwnerOrTrader();
        uint256 balance = address(this).balance;
        if (balance < buyThreshold) revert InsufficientTreasuryBalance(balance, buyThreshold);

        uint256 len = eligibleTokens.length;
        if (len == 0) revert NoEligibleTokens();

        uint256 idx = nextBuyIndex % len;
        address winner = eligibleTokens[idx];

        // Effects-before-interactions: increment cursor BEFORE the swap.
        // Monotonic non-decreasing (modulo applied at READ; never on store) per ARCHITECTURE.md §9.
        unchecked { nextBuyIndex = nextBuyIndex + 1; }

        uint256 ethToSpend = balance < buyThreshold * PER_BUY_CAP_MULTIPLIER
            ? balance
            : buyThreshold * PER_BUY_CAP_MULTIPLIER;

        // The route is operator-built and must target `winner`; if it does not, the
        // balance-delta check in SwapRouter sees no `winner` received and reverts.
        uint256 out = SWAP_ROUTER.swapExactEthForToken{value: ethToSpend}(
            winner,
            commands,
            inputs,
            minOut
        );

        _tranches[winner].pushTranche(winner, out, ethToSpend);
        emit Bought(winner, idx, ethToSpend, out);
    }

    /// @param commands Universal Router command bytes for the token→ETH route (operator-built).
    /// @param inputs   Per-command inputs. The route MUST output native ETH to this Treasury.
    function executeSell(
        address token,
        uint256 trancheIndex,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 minOutSell,
        uint128 minOutBuyback
    ) external nonReentrant {
        _requireOwnerOrTrader();
        BasisLedger.Tranche[] storage arr = _tranches[token];
        if (trancheIndex >= arr.length) revert TrancheOutOfRange(token, trancheIndex);
        BasisLedger.Tranche storage t = arr[trancheIndex];
        if (t.sold) revert TrancheAlreadySold();

        // No approval here: addEligibleToken granted SwapRouter a never-decreased max allowance.
        uint256 ethReceived = SWAP_ROUTER.swapExactTokenForEth(
            token,
            t.amount,
            commands,
            inputs,
            minOutSell
        );

        // Realized-gain floor — measured on actual ETH received, not on an oracle estimate.
        uint256 realized = ethReceived <= t.ethSpent
            ? 0
            : ((ethReceived - t.ethSpent) * 10_000) / t.ethSpent;
        if (realized < sellGainBps) revert RealizedGainBelowFloor(realized, sellGainBps);

        t.sold = true;

        BUYBACK.buyAndBurn{value: ethReceived}(minOutBuyback);

        emit Sold(token, trancheIndex, t.amount, ethReceived, realized);
    }

    // ── View externals ─────────────────────────────────────────────────────────────────────────

    function eligibleTokensLength() external view returns (uint256) {
        return eligibleTokens.length;
    }

    function getEligibleTokens() external view returns (address[] memory) {
        return eligibleTokens;
    }

    function getTranches(address token) external view returns (BasisLedger.Tranche[] memory) {
        return _tranches[token];
    }

    /// @notice Convenience for the dashboard: previews the token that the next `triggerBuy` will
    ///         target. Reverts if no tokens are eligible.
    function previewNextBuyTarget() external view returns (address) {
        uint256 len = eligibleTokens.length;
        if (len == 0) revert NoEligibleTokens();
        return eligibleTokens[nextBuyIndex % len];
    }
}
