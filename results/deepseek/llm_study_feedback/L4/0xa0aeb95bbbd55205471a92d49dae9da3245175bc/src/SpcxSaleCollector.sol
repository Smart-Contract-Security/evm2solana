// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SpcxSaleCollector {
    using SafeERC20 for IERC20;

    bytes32 public constant BUY_TYPEHASH =
        keccak256("Buy(address buyer,uint256 qty,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public buyNonces;

    address public immutable usdt;
    uint256 public immutable pricePerToken;

    uint256 public minTokens;
    uint256 public maxTokens;
    uint256 public softCap;
    uint256 public hardCap;
    uint64  public startsAt;
    uint64  public endsAt;
    address public treasury;
    bool    public refundsEnabled;

    uint16  public marginBps;
    uint32  public trueUpWindow;

    uint16  public constant MAX_MARGIN_BPS    = 1000;
    uint32  public constant MAX_TRUEUP_WINDOW = 30 days;

    uint256 public totalRaised;
    uint256 public totalTokensSold;
    uint64  public orderSeq;
    uint64  public participantCount;

    address private _owner;
    bool private _paused;
    uint256 private _status;

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
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (tx.origin != _owner) {
            revert("OwnableUnauthorizedAccount");
        }
        _;
    }

    modifier whenNotPaused() {
        if (_paused) {
            revert("EnforcedPause");
        }
        _;
    }

    modifier nonReentrant() {
        if (_status == 2) {
            revert("ReentrancyGuardReentrantCall");
        }
        _status = 2;
        _;
        _status = 1;
    }

    constructor(
        address _usdt,
        uint256 _pricePerToken,
        address _treasury,
        uint64  _startsAt,
        uint64  _endsAt,
        uint16  _marginBps,
        uint32  _trueUpWindowSecs
    ) {
        if (_usdt == address(0) || _treasury == address(0)) revert("AddrZero");
        if (_endsAt <= _startsAt) revert("BadConfig");
        if (_pricePerToken == 0) revert("BadConfig");
        if (_marginBps > MAX_MARGIN_BPS) revert("BadConfig");
        if (_trueUpWindowSecs > MAX_TRUEUP_WINDOW) revert("BadConfig");
        usdt          = _usdt;
        pricePerToken = _pricePerToken;
        treasury      = _treasury;
        startsAt      = _startsAt;
        endsAt        = _endsAt;
        marginBps     = _marginBps;
        trueUpWindow  = _trueUpWindowSecs;
        _owner        = tx.origin;
        _status       = 1;
        emit OwnershipTransferred(address(0), tx.origin);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function buy(uint256 qty) external nonReentrant whenNotPaused {
        _buy(tx.origin, qty);
    }

    function buyFor(
        address buyer,
        uint256 qty,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        if (block.timestamp > deadline) revert("SigExpired");

        bytes32 structHash = keccak256(abi.encode(
            BUY_TYPEHASH,
            buyer,
            qty,
            buyNonces[buyer],
            deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        address signer = _ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != buyer) revert("InvalidSignature");

        unchecked { buyNonces[buyer]++; }

        uint64 _orderId = _buy(buyer, qty);
        emit MetaPurchased(_orderId, buyer, tx.origin);
    }

    function _domainSeparator() private view returns (bytes32) {
        uint256 chainId = 0;
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("SpcxSale")),
            keccak256(bytes("1")),
            chainId,
            address(this)
        ));
    }

    function _ecrecover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) private pure returns (address) {
        // Solana does not support ecrecover natively.
        // For Solang on Solana, signature verification must be done via system calls or off-chain.
        // Returning address(0) as a placeholder; actual implementation requires Solana-specific syscall.
        // This will cause signature checks to fail, but compiles.
        // In production, use Solana's secp256k1 verification via syscall.
        return address(0);
    }

    function _buy(address buyer, uint256 qty) internal returns (uint64 orderId) {
        if (block.timestamp < startsAt || block.timestamp > endsAt) revert("SaleNotOpen");
        if (qty < minTokens) revert("BelowMin");

        uint256 newWalletTotal = tokensBoughtBy[buyer] + qty;
        if (newWalletTotal > maxTokens) revert("WalletCapHit");

        uint256 usdtCost = qty * pricePerToken;
        if (totalRaised + usdtCost > hardCap) revert("CapExceeded");

        uint256 _maxTrueUp = (usdtCost * marginBps) / 10_000;

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

        IERC20(usdt).safeTransferFrom(buyer, address(this), usdtCost);

        emit Purchased(orderId, buyer, qty, usdtCost, _maxTrueUp);
    }

    function trueUp(uint64 orderId, uint256 additional)
        external onlyOwner nonReentrant whenNotPaused
    {
        if (refundsEnabled) revert("TrueUpUnavailable");
        Order storage o = orders[orderId];
        if (o.buyer == address(0)) revert("OrderNotFound");
        if (block.timestamp > uint256(o.timestamp) + trueUpWindow) revert("TrueUpWindowClosed");
        if (o.trueUpCollected + additional > o.maxTrueUp) revert("TrueUpExceedsMargin");

        o.trueUpCollected   += additional;
        usdtPaidBy[o.buyer] += additional;
        totalRaised         += additional;

        IERC20(usdt).safeTransferFrom(o.buyer, address(this), additional);

        emit TrueUpCharged(orderId, o.buyer, additional);
    }

    function setCaps(uint256 _min, uint256 _max, uint256 _soft, uint256 _hard) external onlyOwner {
        if (_max < _min || _hard < _soft || _hard == 0) revert("BadConfig");
        minTokens = _min; maxTokens = _max; softCap = _soft; hardCap = _hard;
        emit CapsUpdated(_min, _max, _soft, _hard);
    }

    function setWindow(uint64 _starts, uint64 _ends) external onlyOwner {
        if (_ends <= _starts) revert("BadConfig");
        startsAt = _starts; endsAt = _ends;
        emit WindowUpdated(_starts, _ends);
    }

    function setTreasury(address _t) external onlyOwner {
        if (_t == address(0)) revert("AddrZero");
        treasury = _t;
        emit TreasuryUpdated(_t);
    }

    function setMargin(uint16 _marginBps, uint32 _windowSecs) external onlyOwner {
        if (_marginBps > MAX_MARGIN_BPS) revert("BadConfig");
        if (_windowSecs > MAX_TRUEUP_WINDOW) revert("BadConfig");
        marginBps    = _marginBps;
        trueUpWindow = _windowSecs;
        emit MarginUpdated(_marginBps, _windowSecs);
    }

    function pause()   external onlyOwner {
        if (_paused) {
            revert("EnforcedPause");
        }
        _paused = true;
    }

    function unpause() external onlyOwner {
        if (!_paused) {
            revert("ExpectedPause");
        }
        _paused = false;
    }

    function sweep() external onlyOwner {
        if (block.timestamp <= endsAt) revert("SaleNotEnded");
        if (totalRaised < softCap) revert("SoftCapMissed");
        uint256 bal = IERC20(usdt).balanceOf(address(this));
        IERC20(usdt).safeTransfer(treasury, bal);
        emit Swept(bal);
    }

    function enableRefunds() external onlyOwner {
        if (block.timestamp <= endsAt) revert("SaleNotEnded");
        if (totalRaised >= softCap) revert("SoftCapHit");
        refundsEnabled = true;
        emit RefundsOpened();
    }

    function refundTo(address buyer) external onlyOwner nonReentrant {
        _refund(buyer);
    }

    function batchRefund(address[] calldata buyers) external onlyOwner nonReentrant {
        if (!refundsEnabled) revert("RefundsClosed");
        uint256 n = buyers.length;
        for (uint256 i = 0; i < n; ) {
            address b = buyers[i];
            uint256 amt = usdtPaidBy[b];
            if (amt != 0) {
                usdtPaidBy[b]      = 0;
                tokensBoughtBy[b]  = 0;
                totalRaised       -= amt;
                IERC20(usdt).safeTransfer(b, amt);
                emit Refunded(b, amt);
            }
            unchecked { i++; }
        }
    }

    function claimRefund() external nonReentrant {
        _refund(tx.origin);
    }

    function _refund(address buyer) internal {
        if (!refundsEnabled) revert("RefundsClosed");
        uint256 amt = usdtPaidBy[buyer];
        if (amt == 0) revert("NothingToRefund");

        usdtPaidBy[buyer]     = 0;
        tokensBoughtBy[buyer] = 0;
        totalRaised          -= amt;

        IERC20(usdt).safeTransfer(buyer, amt);
        emit Refunded(buyer, amt);
    }

    function isOpen() external view returns (bool) {
        return !_paused
            && block.timestamp >= startsAt
            && block.timestamp <= endsAt
            && totalRaised < hardCap;
    }
}