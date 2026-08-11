// SPDX-License-Identifier: MIT

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Treasury
/// @notice Holds ETH from fee harvesting; deploys it into a team-curated eligible-token universe
///         via deterministic round-robin buys; tracks per-token tranches; routes sale proceeds
///         to the TFLO buyback. v1 design: owner-only `triggerBuy` / `executeSell` with caller-
///         supplied `minOut` for slippage protection (see ARCHITECTURE.md §1 centralization note).
contract Treasury is Ownable {

    // ── Tranche struct (inlined from BasisLedger) ──────────────────────────────────────────────
    struct Tranche {
        address token;
        uint64 amount;
        uint64 ethSpent;
        bool sold;
    }

    // ── External refs (immutable) ──────────────────────────────────────────────────────────────
    address public immutable SWAP_ROUTER;
    address public immutable BUYBACK;

    // ── Upper bounds only (from ARCHITECTURE.md §3.1, §3.2) ────────────────────────────────────
    uint64 public constant MAX_BUY_THRESHOLD = 10 ether;
    uint16 public constant MAX_SELL_GAIN_BPS = 5000;
    uint8 public constant MAX_ELIGIBLE_TOKENS = 50;
    uint8 public constant PER_BUY_CAP_MULTIPLIER = 2;

    // ── Storage (see ARCHITECTURE.md §5) ───────────────────────────────────────────────────────
    mapping(address => Tranche[]) public _tranches;
    address[] public eligibleTokens;
    mapping(address => bool) public isEligible;
    uint64 public nextBuyIndex;

    uint64 public buyThreshold;
    uint16 public sellGainBps;

    /// @notice Secondary caller authorized to invoke `triggerBuy` / `executeSell`.
    address public trader;

    // ── Events ─────────────────────────────────────────────────────────────────────────────────
    event Bought(address indexed winner, uint64 indexed idx, uint64 ethSpent, uint64 tokenOut);
    event Sold(
        address indexed token,
        uint64 indexed trancheIndex,
        uint64 amount,
        uint64 ethReceived,
        uint64 realizedGainBps
    );
    event EligibleAdded(address indexed token);
    event EligibleRemoved(address indexed token);
    event BuyThresholdSet(uint64 newValue);
    event SellGainBpsSet(uint16 newValue);
    event TraderSet(address indexed oldTrader, address indexed newTrader);

    /// @param swapRouter  SwapRouter — forwards operator-built Universal Router routes.
    /// @param buyback     TFLOBuyback — final hop on every sell.
    /// @param defaultBuyThreshold Initial buy threshold (must be within MAX).
    /// @param defaultSellGainBps  Initial sell-gain floor (must be within MAX).
    constructor(
        address swapRouter,
        address buyback,
        uint64 defaultBuyThreshold,
        uint16 defaultSellGainBps
    ) Ownable() {
        if (defaultBuyThreshold > MAX_BUY_THRESHOLD) {
            revert("BuyThresholdOutOfBounds");
        }
        if (defaultSellGainBps > MAX_SELL_GAIN_BPS) {
            revert("SellGainBpsOutOfBounds");
        }

        SWAP_ROUTER = swapRouter;
        BUYBACK = buyback;

        buyThreshold = defaultBuyThreshold;
        sellGainBps = defaultSellGainBps;
    }

    // ── Owner config setters ───────────────────────────────────────────────────────────────────

    function setBuyThreshold(uint64 value) external onlyOwner {
        if (value > MAX_BUY_THRESHOLD) {
            revert("BuyThresholdOutOfBounds");
        }
        buyThreshold = value;
        emit BuyThresholdSet(value);
    }

    function setSellGainBps(uint16 value) external onlyOwner {
        if (value > MAX_SELL_GAIN_BPS) {
            revert("SellGainBpsOutOfBounds");
        }
        sellGainBps = value;
        emit SellGainBpsSet(value);
    }

    function setTrader(address newTrader) external onlyOwner {
        address old = trader;
        trader = newTrader;
        emit TraderSet(old, newTrader);
    }

    function addEligibleToken(address token) external onlyOwner {
        if (eligibleTokens.length >= MAX_ELIGIBLE_TOKENS) revert("EligibleListFull");
        if (isEligible[token]) revert("AlreadyEligible");

        eligibleTokens.push(token);
        isEligible[token] = true;

        emit EligibleAdded(token);
    }

    function removeEligibleToken(address token) external onlyOwner {
        if (!isEligible[token]) revert("NotEligible");

        uint64 len = uint64(eligibleTokens.length);
        for (uint64 i = 0; i < len; ) {
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

        emit EligibleRemoved(token);
    }

    // ── Owner-or-trader trade triggers ─────────────────────────────────────────────────────────

    function _requireOwnerOrTrader() internal view {
        if (tx.accounts.dataAccount.key != owner() && tx.accounts.dataAccount.key != trader) revert("NotOwnerOrTrader");
    }

    function triggerBuy(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint64 minOut
    ) external {
        _requireOwnerOrTrader();
        uint64 balance = uint64(tx.accounts.dataAccount.lamports);
        if (balance < buyThreshold) revert("InsufficientTreasuryBalance");

        uint64 len = uint64(eligibleTokens.length);
        if (len == 0) revert("NoEligibleTokens");

        uint64 idx = nextBuyIndex % len;
        address winner = eligibleTokens[idx];

        unchecked { nextBuyIndex = nextBuyIndex + 1; }

        uint64 ethToSpend = balance < buyThreshold * PER_BUY_CAP_MULTIPLIER
            ? balance
            : buyThreshold * PER_BUY_CAP_MULTIPLIER;

        // External call to SwapRouter
        (bool success, bytes memory returnData) = SWAP_ROUTER.call(
            abi.encodeWithSignature(
                "swapExactEthForToken(address,bytes,bytes[],uint64)",
                winner,
                commands,
                inputs,
                minOut
            )
        );
        if (!success) revert("SwapRouterBuyFailed");
        uint64 out = abi.decode(returnData, (uint64));

        _tranches[winner].push(Tranche(winner, out, ethToSpend, false));
        emit Bought(winner, idx, ethToSpend, out);
    }

    function executeSell(
        address token,
        uint64 trancheIndex,
        bytes calldata commands,
        bytes[] calldata inputs,
        uint64 minOutSell,
        uint64 minOutBuyback
    ) external {
        _requireOwnerOrTrader();
        Tranche[] storage arr = _tranches[token];
        if (trancheIndex >= arr.length) revert("TrancheOutOfRange");
        Tranche storage t = arr[trancheIndex];
        if (t.sold) revert("TrancheAlreadySold");

        // External call to SwapRouter
        (bool success, bytes memory returnData) = SWAP_ROUTER.call(
            abi.encodeWithSignature(
                "swapExactTokenForEth(address,uint64,bytes,bytes[],uint64)",
                token,
                t.amount,
                commands,
                inputs,
                minOutSell
            )
        );
        if (!success) revert("SwapRouterSellFailed");
        uint64 ethReceived = abi.decode(returnData, (uint64));

        uint64 realized = ethReceived <= t.ethSpent
            ? 0
            : ((ethReceived - t.ethSpent) * 10_000) / t.ethSpent;
        if (realized < sellGainBps) revert("RealizedGainBelowFloor");

        t.sold = true;

        // External call to Buyback
        (bool buybackSuccess, ) = BUYBACK.call(
            abi.encodeWithSignature("buyAndBurn(uint64)", minOutBuyback)
        );
        if (!buybackSuccess) revert("BuybackFailed");

        emit Sold(token, trancheIndex, t.amount, ethReceived, realized);
    }

    // ── View externals ─────────────────────────────────────────────────────────────────────────

    function eligibleTokensLength() external view returns (uint64) {
        return uint64(eligibleTokens.length);
    }

    function getEligibleTokens() external view returns (address[] memory) {
        return eligibleTokens;
    }

    function getTranches(address token) external view returns (Tranche[] memory) {
        return _tranches[token];
    }

    function previewNextBuyTarget() external view returns (address) {
        uint64 len = uint64(eligibleTokens.length);
        if (len == 0) revert("NoEligibleTokens");
        return eligibleTokens[nextBuyIndex % len];
    }
}