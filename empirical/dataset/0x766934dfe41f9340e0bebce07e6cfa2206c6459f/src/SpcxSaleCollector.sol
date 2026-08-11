// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title SPCX Sale Collector
 * @notice Accepts USDT for $SPCX. Same contract code is deployed twice:
 *           - on BNB Chain with USDT-BSC  (18 decimals)
 *           - on Ethereum  with USDT-ETH  ( 6 decimals)
 *
 *         $SPCX is delivered out-of-band on BNB Chain by an off-chain worker
 *         that watches the Purchased event. (Token lives on BSC only.)
 *
 *         Per-purchase flow:
 *           1. Buyer approves this contract for `qty * pricePerToken * (1 + uiMargin)` USDT
 *              (the UI margin is purely advisory; the contract pulls only the exact cost.)
 *           2. Buyer calls buy(qty).
 *           3. Contract pulls `qty * pricePerToken` USDT via SafeERC20.
 *           4. Emits Purchased(orderId, buyer, qty, usdtPaid).
 *           5. Off-chain worker delivers $SPCX on BSC to `buyer`.
 *
 *         Refunds:
 *           If softCap is not reached by endsAt, owner enables refunds and
 *           every contributor can pull their USDT back from this contract.
 *
 *         Decimals:
 *           `pricePerToken` is in USDT base units.
 *             - BSC (18 dec):  $150  =>  150e18
 *             - ETH ( 6 dec):  $150  =>  150e6
 *           `qty` is whole $SPCX units (not 18-dec wei). Max supply is 1M
 *             so qty is small and multiplications stay far from overflow.
 */
contract SpcxSaleCollector is Ownable2Step, ReentrancyGuard, Pausable, EIP712 {
    using SafeERC20 for IERC20;

    /* ============================ meta-tx constants ========================== */

    // EIP-712 typehash for the off-chain buy authorization message.
    // Buyer signs this hashed struct; anyone (typically the project's relayer)
    // submits it via buyFor() and pays the gas.
    bytes32 public constant BUY_TYPEHASH =
        keccak256("Buy(address buyer,uint256 qty,uint256 nonce,uint256 deadline)");

    /// @notice Per-buyer nonce for meta-tx signatures. Each successful buyFor()
    ///         consumes the current nonce; replays revert.
    mapping(address => uint256) public buyNonces;

    /* ============================ immutable config ============================ */

    IERC20  public immutable usdt;
    uint256 public immutable pricePerToken;   // USDT base units per 1 SPCX

    /* ============================ mutable config ============================== */

    uint256 public minTokens;
    uint256 public maxTokens;
    uint256 public softCap;     // in USDT base units
    uint256 public hardCap;     // in USDT base units
    uint64  public startsAt;
    uint64  public endsAt;
    address public treasury;
    bool    public refundsEnabled;

    // True-up (post-buy margin settlement) config. Per-order maxTrueUp is
    // LOCKED at buy time using the marginBps that was active then, so admin
    // changes to marginBps do not retroactively widen existing buyers' caps.
    uint16  public marginBps;            // basis points; e.g. 500 = 5%. Hard cap: 1000 (=10%)
    uint32  public trueUpWindow;         // seconds after buy that owner may call trueUp. Hard cap: 30 days

    uint16  public constant MAX_MARGIN_BPS    = 1000;        // 10% hard ceiling on admin-settable margin
    uint32  public constant MAX_TRUEUP_WINDOW = 30 days;     // 30-day ceiling on admin-settable window

    /* ============================ live state ================================== */

    uint256 public totalRaised;       // USDT collected (gross; includes any true-ups)
    uint256 public totalTokensSold;   // cumulative whole SPCX sold
    uint64  public orderSeq;
    uint64  public participantCount;

    struct Order {
        address buyer;
        uint64  timestamp;        // when buy() executed
        uint256 baseCost;         // USDT pulled at buy()
        uint256 maxTrueUp;        // = baseCost * marginBps_at_buy / 10000   (immutable per order)
        uint256 trueUpCollected;  // sum of trueUp pulls so far
    }
    mapping(uint64 => Order)    public orders;
    mapping(address => uint256) public tokensBoughtBy;
    mapping(address => uint256) public usdtPaidBy;        // base + all true-ups (used by refund)
    mapping(address => bool)    public hasParticipated;

    /* ============================ events ===================================== */

    event Purchased(uint64 indexed orderId, address indexed buyer, uint256 tokenQty, uint256 baseCost, uint256 maxTrueUp);
    event MetaPurchased(uint64 indexed orderId, address indexed buyer, address indexed relayer);
    event TrueUpCharged(uint64 indexed orderId, address indexed buyer, uint256 amount);
    event Refunded(address indexed buyer, uint256 usdtRefunded);
    event TreasuryUpdated(address indexed newTreasury);
    event CapsUpdated(uint256 minTokens, uint256 maxTokens, uint256 softCap, uint256 hardCap);
    event WindowUpdated(uint64 startsAt, uint64 endsAt);
    event MarginUpdated(uint16 marginBps, uint32 trueUpWindow);
    event Swept(uint256 amount);
    event RefundsOpened();

    /* ============================ errors ===================================== */

    error SaleNotOpen();
    error CapExceeded();
    error BelowMin();
    error WalletCapHit();
    error SaleNotEnded();
    error SoftCapHit();
    error SoftCapMissed();
    error NothingToRefund();
    error RefundsClosed();
    error AddrZero();
    error BadConfig();
    error OrderNotFound();
    error TrueUpWindowClosed();
    error TrueUpExceedsMargin();
    error TrueUpUnavailable();
    error SigExpired();
    error InvalidSignature();

    /* ============================ constructor ================================ */

    constructor(
        address _usdt,
        uint256 _pricePerToken,
        address _treasury,
        uint64  _startsAt,
        uint64  _endsAt,
        uint16  _marginBps,        // e.g. 500 = 5%
        uint32  _trueUpWindowSecs  // e.g. 30 days = 2_592_000
    ) Ownable(msg.sender) EIP712("SpcxSale", "1") {
        if (_usdt == address(0) || _treasury == address(0)) revert AddrZero();
        if (_endsAt <= _startsAt) revert BadConfig();
        if (_pricePerToken == 0) revert BadConfig();
        if (_marginBps > MAX_MARGIN_BPS) revert BadConfig();
        if (_trueUpWindowSecs > MAX_TRUEUP_WINDOW) revert BadConfig();
        usdt          = IERC20(_usdt);
        pricePerToken = _pricePerToken;
        treasury      = _treasury;
        startsAt      = _startsAt;
        endsAt        = _endsAt;
        marginBps     = _marginBps;
        trueUpWindow  = _trueUpWindowSecs;
    }

    /* ============================ buy ======================================== */

    /**
     * @notice Buy `qty` whole $SPCX. Pulls `qty * pricePerToken` USDT from msg.sender.
     *         Caller must have approved at least `qty * pricePerToken` to this contract.
     */
    /**
     * @notice Direct buy. Buyer pays gas. Always available as a fallback if the
     *         project's relayer is down or the buyer prefers self-service.
     */
    function buy(uint256 qty) external nonReentrant whenNotPaused {
        _buy(msg.sender, qty);
    }

    /**
     * @notice Meta-tx buy. Anyone (typically the project's relayer) submits the tx
     *         on behalf of `buyer`, who authorized it by signing a Buy struct off-chain.
     *         The relayer pays gas; the buyer's only cost is the USDT itself.
     *
     *         Signature payload (EIP-712):
     *           Buy(address buyer, uint256 qty, uint256 nonce, uint256 deadline)
     *
     * @dev Nonce auto-increments per buyer so signatures cannot be replayed.
     *      Deadline is a unix timestamp; the tx must land before it expires.
     *      USDT allowance + balance must be in place at execution time —
     *      the relayer should pre-check these to avoid wasting gas on a revert.
     */
    function buyFor(
        address buyer,
        uint256 qty,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        if (block.timestamp > deadline) revert SigExpired();

        bytes32 structHash = keccak256(abi.encode(
            BUY_TYPEHASH,
            buyer,
            qty,
            buyNonces[buyer],
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer == address(0) || signer != buyer) revert InvalidSignature();

        unchecked { buyNonces[buyer]++; }

        uint64 _orderId = _buy(buyer, qty);
        emit MetaPurchased(_orderId, buyer, msg.sender);
    }

    /**
     * @dev Shared buy logic. Pulls USDT from `buyer` (the contract uses
     *      buyer's pre-existing USDT allowance to this contract). The caller of
     *      buy() is the buyer themselves; the caller of buyFor() is the relayer
     *      who pays gas — but in both cases the USDT comes from `buyer`.
     */
    function _buy(address buyer, uint256 qty) internal returns (uint64 orderId) {
        if (block.timestamp < startsAt || block.timestamp > endsAt) revert SaleNotOpen();
        if (qty < minTokens) revert BelowMin();

        uint256 newWalletTotal = tokensBoughtBy[buyer] + qty;
        if (newWalletTotal > maxTokens) revert WalletCapHit();

        uint256 usdtCost = qty * pricePerToken;
        if (totalRaised + usdtCost > hardCap) revert CapExceeded();

        // Lock the per-order maxTrueUp at current margin (admin changes can't widen it).
        uint256 _maxTrueUp = (usdtCost * marginBps) / 10_000;

        // ---- effects ----
        tokensBoughtBy[buyer] = newWalletTotal;
        usdtPaidBy[buyer]    += usdtCost;
        totalRaised          += usdtCost;
        totalTokensSold      += qty;
        if (!hasParticipated[buyer]) {
            hasParticipated[buyer] = true;
            unchecked { participantCount++; }
        }
        unchecked { orderSeq++; }
        orderId = orderSeq;

        orders[orderId] = Order({
            buyer:           buyer,
            timestamp:       uint64(block.timestamp),
            baseCost:        usdtCost,
            maxTrueUp:       _maxTrueUp,
            trueUpCollected: 0
        });

        // ---- interactions ----
        usdt.safeTransferFrom(buyer, address(this), usdtCost);

        emit Purchased(orderId, buyer, qty, usdtCost, _maxTrueUp);
    }

    /**
     * @notice Admin-initiated buy on behalf of `buyer`. Uses the buyer's existing
     *         USDT allowance to this contract — same effect as if the buyer
     *         called buy(qty) themselves. Used for support flows where a buyer
     *         has approved but not completed the purchase, OR where the project
     *         pre-arranges a sale via off-chain channels.
     *
     *         The buyer must have:
     *           - sufficient USDT balance
     *           - sufficient USDT allowance to this contract
     *
     *         If either is missing, the safeTransferFrom inside _buy reverts
     *         and no order is created.
     */
    function chargeBuy(address buyer, uint256 qty) external onlyOwner nonReentrant whenNotPaused {
        _buy(buyer, qty);
    }

    /* ============================ true-up ==================================== */

    /**
     * @notice Pull additional USDT from a buyer's still-active allowance, within
     *         the margin that was locked at their buy() and the time window from buy.
     *         Owner-only. Use sparingly — every adjustment emits a public event.
     *
     * @param  orderId    The orderId from the original Purchased event.
     * @param  additional The extra USDT (base units) to pull. Must not push that
     *                    order's running total past its locked maxTrueUp.
     *
     * @dev Reverts if:
     *       - order doesn't exist
     *       - paused
     *       - refundsEnabled (we don't take more if soft cap was missed)
     *       - block.timestamp > order.timestamp + trueUpWindow
     *       - additional + trueUpCollected > maxTrueUp
     *       - usdt.safeTransferFrom reverts (allowance revoked / insufficient balance)
     */
    function trueUp(uint64 orderId, uint256 additional)
        external onlyOwner nonReentrant whenNotPaused
    {
        if (refundsEnabled) revert TrueUpUnavailable();
        Order storage o = orders[orderId];
        if (o.buyer == address(0)) revert OrderNotFound();
        if (block.timestamp > uint256(o.timestamp) + trueUpWindow) revert TrueUpWindowClosed();
        if (o.trueUpCollected + additional > o.maxTrueUp) revert TrueUpExceedsMargin();

        // ---- effects ----
        o.trueUpCollected   += additional;
        usdtPaidBy[o.buyer] += additional;
        totalRaised         += additional;

        // ---- interactions ----
        usdt.safeTransferFrom(o.buyer, address(this), additional);

        emit TrueUpCharged(orderId, o.buyer, additional);
    }

    /* ============================ admin ====================================== */

    function setCaps(uint256 _min, uint256 _max, uint256 _soft, uint256 _hard) external onlyOwner {
        if (_max < _min || _hard < _soft || _hard == 0) revert BadConfig();
        minTokens = _min; maxTokens = _max; softCap = _soft; hardCap = _hard;
        emit CapsUpdated(_min, _max, _soft, _hard);
    }

    function setWindow(uint64 _starts, uint64 _ends) external onlyOwner {
        if (_ends <= _starts) revert BadConfig();
        startsAt = _starts; endsAt = _ends;
        emit WindowUpdated(_starts, _ends);
    }

    function setTreasury(address _t) external onlyOwner {
        if (_t == address(0)) revert AddrZero();
        treasury = _t;
        emit TreasuryUpdated(_t);
    }

    /**
     * @notice Update the true-up margin and window. Affects FUTURE orders only —
     *         orders already in `orders[]` keep the maxTrueUp they were created with.
     *         Both values are capped by MAX_MARGIN_BPS (10%) and MAX_TRUEUP_WINDOW (30d)
     *         so even a compromised owner can't drain wallets beyond those limits.
     */
    function setMargin(uint16 _marginBps, uint32 _windowSecs) external onlyOwner {
        if (_marginBps > MAX_MARGIN_BPS) revert BadConfig();
        if (_windowSecs > MAX_TRUEUP_WINDOW) revert BadConfig();
        marginBps    = _marginBps;
        trueUpWindow = _windowSecs;
        emit MarginUpdated(_marginBps, _windowSecs);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /**
     * @notice Move all collected USDT (incl. any donations) to treasury.
     *         Only after the sale window has ended AND soft cap has been hit.
     */
    function sweep() external onlyOwner {
        if (block.timestamp <= endsAt) revert SaleNotEnded();
        if (totalRaised < softCap) revert SoftCapMissed();
        uint256 bal = usdt.balanceOf(address(this));
        usdt.safeTransfer(treasury, bal);
        emit Swept(bal);
    }

    /**
     * @notice Open the refund window when soft cap was missed at sale end.
     */
    function enableRefunds() external onlyOwner {
        if (block.timestamp <= endsAt) revert SaleNotEnded();
        if (totalRaised >= softCap) revert SoftCapHit();
        refundsEnabled = true;
        emit RefundsOpened();
    }

    /* ============================ refund ===================================== */

    /**
     * @notice Admin pushes refund to a single buyer. Primary refund UX —
     *         buyer does nothing, USDT just appears in their wallet.
     */
    function refundTo(address buyer) external onlyOwner nonReentrant {
        _refund(buyer);
    }

    /**
     * @notice Admin pushes refunds to a batch of buyers in one tx. Skips entries
     *         that are already at zero (e.g. already refunded) instead of reverting,
     *         so a single dust address doesn't sink the whole batch.
     *         Keep batch size modest (<200) to stay under block gas limit.
     */
    function batchRefund(address[] calldata buyers) external onlyOwner nonReentrant {
        if (!refundsEnabled) revert RefundsClosed();
        uint256 n = buyers.length;
        for (uint256 i = 0; i < n; ) {
            address b = buyers[i];
            uint256 amt = usdtPaidBy[b];
            if (amt != 0) {
                usdtPaidBy[b]      = 0;
                tokensBoughtBy[b]  = 0;
                totalRaised       -= amt;
                usdt.safeTransfer(b, amt);
                emit Refunded(b, amt);
            }
            unchecked { i++; }
        }
    }

    /**
     * @notice Buyer self-rescue. Kept as a trust-minimizing safety net —
     *         if the admin push pattern ever fails (key loss, abandoned project),
     *         buyers can always pull their refund directly. Not exposed in the UI;
     *         callable via BscScan/Etherscan write tab if ever needed.
     */
    function claimRefund() external nonReentrant {
        _refund(msg.sender);
    }

    function _refund(address buyer) internal {
        if (!refundsEnabled) revert RefundsClosed();
        uint256 amt = usdtPaidBy[buyer];
        if (amt == 0) revert NothingToRefund();

        usdtPaidBy[buyer]     = 0;
        tokensBoughtBy[buyer] = 0;
        totalRaised          -= amt;

        usdt.safeTransfer(buyer, amt);
        emit Refunded(buyer, amt);
    }

    /* ============================ views ====================================== */

    function isOpen() external view returns (bool) {
        return !paused()
            && block.timestamp >= startsAt
            && block.timestamp <= endsAt
            && totalRaised < hardCap;
    }
}
