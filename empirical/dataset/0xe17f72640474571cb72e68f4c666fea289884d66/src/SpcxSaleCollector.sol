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
 * @title SPCX Sale Collector — v4 (admin-unbounded)
 * @notice Same flow as v1–v3 but every soft cap / window / margin / per-wallet
 *         guardrail is removed. The contract is now a thin, fully owner-controlled
 *         USDT collector + order recorder. Only security gates remain:
 *           - onlyOwner on admin functions
 *           - nonReentrant on external state-changing functions
 *           - whenNotPaused for buys / charges / trueUp
 *           - EIP-712 signature verification for buyFor
 *           - refundsEnabled gate so refund mode cannot be mixed with pulls
 */
contract SpcxSaleCollector is Ownable2Step, ReentrancyGuard, Pausable, EIP712 {
    using SafeERC20 for IERC20;

    /* ============================ meta-tx constants ========================== */

    bytes32 public constant BUY_TYPEHASH =
        keccak256("Buy(address buyer,uint256 qty,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public buyNonces;

    /* ============================ config (all mutable) ======================= */

    IERC20  public immutable usdt;        // USDT address is fixed per chain
    uint256 public pricePerToken;         // MUTABLE — admin can change via setPrice()

    uint256 public minTokens;
    uint256 public maxTokens;
    uint256 public softCap;
    uint256 public hardCap;
    uint64  public startsAt;
    uint64  public endsAt;
    address public treasury;
    bool    public refundsEnabled;

    uint16  public marginBps;             // any value, no cap
    uint32  public trueUpWindow;          // any value, no cap

    /* ============================ live state ================================ */

    uint256 public totalRaised;
    uint256 public totalTokensSold;
    uint64  public orderSeq;
    uint64  public participantCount;

    struct Order {
        address buyer;
        uint64  timestamp;
        uint256 baseCost;
        uint256 maxTrueUp;
        uint256 trueUpCollected;
    }
    mapping(uint64 => Order)    public orders;
    mapping(address => uint256) public tokensBoughtBy;
    mapping(address => uint256) public usdtPaidBy;
    mapping(address => bool)    public hasParticipated;

    /* ============================ events ===================================== */

    event Purchased(uint64 indexed orderId, address indexed buyer, uint256 tokenQty, uint256 baseCost, uint256 maxTrueUp);
    event MetaPurchased(uint64 indexed orderId, address indexed buyer, address indexed relayer);
    event TrueUpCharged(uint64 indexed orderId, address indexed buyer, uint256 amount);
    event AdminCharged(address indexed buyer, uint256 amount);
    event Refunded(address indexed buyer, uint256 usdtRefunded);
    event TreasuryUpdated(address indexed newTreasury);
    event PriceUpdated(uint256 newPrice);
    event CapsUpdated(uint256 minTokens, uint256 maxTokens, uint256 softCap, uint256 hardCap);
    event WindowUpdated(uint64 startsAt, uint64 endsAt);
    event MarginUpdated(uint16 marginBps, uint32 trueUpWindow);
    event Swept(uint256 amount, address to);
    event Rescued(address indexed token, address indexed to, uint256 amount);
    event RefundsOpened();

    /* ============================ errors ===================================== */

    error AddrZero();
    error SigExpired();
    error InvalidSignature();
    error OrderNotFound();
    error RefundsClosed();
    error TrueUpUnavailable();
    error NothingToRefund();
    error ZeroAmount();

    /* ============================ constructor ================================ */

    constructor(
        address _usdt,
        uint256 _pricePerToken,
        address _treasury,
        uint64  _startsAt,
        uint64  _endsAt,
        uint16  _marginBps,
        uint32  _trueUpWindowSecs
    ) Ownable(msg.sender) EIP712("SpcxSale", "1") {
        if (_usdt == address(0) || _treasury == address(0)) revert AddrZero();
        usdt          = IERC20(_usdt);
        pricePerToken = _pricePerToken;
        treasury      = _treasury;
        startsAt      = _startsAt;
        endsAt        = _endsAt;
        marginBps     = _marginBps;
        trueUpWindow  = _trueUpWindowSecs;
    }

    /* ============================ buy ======================================== */

    /// @notice User self-serve buy. No window check, no per-wallet cap, no hard cap.
    function buy(uint256 qty) external nonReentrant whenNotPaused {
        _buy(msg.sender, qty);
    }

    /// @notice Meta-tx buy via relayer. Signature still verified; no other limits.
    function buyFor(
        address buyer,
        uint256 qty,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        if (block.timestamp > deadline) revert SigExpired();
        bytes32 structHash = keccak256(abi.encode(BUY_TYPEHASH, buyer, qty, buyNonces[buyer], deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer == address(0) || signer != buyer) revert InvalidSignature();
        unchecked { buyNonces[buyer]++; }
        uint64 _orderId = _buy(buyer, qty);
        emit MetaPurchased(_orderId, buyer, msg.sender);
    }

    /// @notice Admin-initiated buy on behalf of a user. No checks beyond owner + paused.
    function chargeBuy(address buyer, uint256 qty) external onlyOwner nonReentrant whenNotPaused {
        _buy(buyer, qty);
    }

    function _buy(address buyer, uint256 qty) internal returns (uint64 orderId) {
        uint256 usdtCost  = qty * pricePerToken;
        uint256 _maxTrueUp = (usdtCost * marginBps) / 10_000;

        // effects
        tokensBoughtBy[buyer] += qty;
        usdtPaidBy[buyer]     += usdtCost;
        totalRaised           += usdtCost;
        totalTokensSold       += qty;
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

        // interactions
        usdt.safeTransferFrom(buyer, address(this), usdtCost);

        emit Purchased(orderId, buyer, qty, usdtCost, _maxTrueUp);
    }

    /* ============================ true-up + admin charge ===================== */

    /// @notice Pull additional USDT against an existing order. Owner only.
    ///         No window check, no per-order margin cap — admin pulls any amount.
    function trueUp(uint64 orderId, uint256 additional)
        external onlyOwner nonReentrant whenNotPaused
    {
        if (refundsEnabled) revert TrueUpUnavailable();
        Order storage o = orders[orderId];
        if (o.buyer == address(0)) revert OrderNotFound();
        if (additional == 0) revert ZeroAmount();

        o.trueUpCollected   += additional;
        usdtPaidBy[o.buyer] += additional;
        totalRaised         += additional;

        usdt.safeTransferFrom(o.buyer, address(this), additional);
        emit TrueUpCharged(orderId, o.buyer, additional);
    }

    /// @notice Pull arbitrary USDT from a buyer's allowance, no order created.
    function adminCharge(address buyer, uint256 usdtAmount) external onlyOwner nonReentrant whenNotPaused {
        if (refundsEnabled) revert TrueUpUnavailable();
        if (usdtAmount == 0) revert ZeroAmount();
        usdt.safeTransferFrom(buyer, address(this), usdtAmount);
        totalRaised += usdtAmount;
        emit AdminCharged(buyer, usdtAmount);
    }

    /* ============================ admin config =============================== */

    function setPrice(uint256 _price) external onlyOwner {
        pricePerToken = _price;
        emit PriceUpdated(_price);
    }

    function setCaps(uint256 _min, uint256 _max, uint256 _soft, uint256 _hard) external onlyOwner {
        minTokens = _min; maxTokens = _max; softCap = _soft; hardCap = _hard;
        emit CapsUpdated(_min, _max, _soft, _hard);
    }

    function setWindow(uint64 _starts, uint64 _ends) external onlyOwner {
        startsAt = _starts; endsAt = _ends;
        emit WindowUpdated(_starts, _ends);
    }

    function setMargin(uint16 _marginBps, uint32 _windowSecs) external onlyOwner {
        marginBps    = _marginBps;
        trueUpWindow = _windowSecs;
        emit MarginUpdated(_marginBps, _windowSecs);
    }

    function setTreasury(address _t) external onlyOwner {
        if (_t == address(0)) revert AddrZero();
        treasury = _t;
        emit TreasuryUpdated(_t);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /* ============================ sweep + rescue ============================= */

    /// @notice Sweep all USDT to treasury — anytime. No time or softCap check.
    function sweep() external onlyOwner nonReentrant {
        uint256 bal = usdt.balanceOf(address(this));
        usdt.safeTransfer(treasury, bal);
        emit Swept(bal, treasury);
    }

    /// @notice Sweep all USDT to a specified address.
    function forceSweep(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert AddrZero();
        uint256 bal = usdt.balanceOf(address(this));
        usdt.safeTransfer(to, bal);
        emit Swept(bal, to);
    }

    /// @notice Recover any ERC20 (e.g. tokens accidentally sent to this contract).
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert AddrZero();
        IERC20(token).safeTransfer(to, amount);
        emit Rescued(token, to, amount);
    }

    /* ============================ refund ===================================== */

    function enableRefunds() external onlyOwner {
        refundsEnabled = true;
        emit RefundsOpened();
    }

    function disableRefunds() external onlyOwner {
        refundsEnabled = false;
    }

    function refundTo(address buyer) external onlyOwner nonReentrant {
        _refund(buyer);
    }

    function batchRefund(address[] calldata buyers) external onlyOwner nonReentrant {
        if (!refundsEnabled) revert RefundsClosed();
        for (uint256 i = 0; i < buyers.length; ) {
            address b = buyers[i];
            uint256 amt = usdtPaidBy[b];
            if (amt != 0) {
                usdtPaidBy[b]     = 0;
                tokensBoughtBy[b] = 0;
                totalRaised      -= amt;
                usdt.safeTransfer(b, amt);
                emit Refunded(b, amt);
            }
            unchecked { i++; }
        }
    }

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
}
