// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

contract SpcxSaleCollector {
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

    address public owner;
    address public pendingOwner;

    bool public paused;

    bool private _locked;

    constructor(
        address _usdt,
        uint256 _pricePerToken,
        address _treasury,
        uint64  _startsAt,
        uint64  _endsAt,
        uint16  _marginBps,
        uint32  _trueUpWindowSecs
    ) {
        require(_usdt != address(0) && _treasury != address(0), "AddrZero");
        require(_endsAt > _startsAt, "BadConfig");
        require(_pricePerToken != 0, "BadConfig");
        require(_marginBps <= MAX_MARGIN_BPS, "BadConfig");
        require(_trueUpWindowSecs <= MAX_TRUEUP_WINDOW, "BadConfig");
        usdt          = _usdt;
        pricePerToken = _pricePerToken;
        treasury      = _treasury;
        startsAt      = _startsAt;
        endsAt        = _endsAt;
        marginBps     = _marginBps;
        trueUpWindow  = _trueUpWindowSecs;
        owner         = tx.accounts.dataAccount.key;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    function buy(uint256 qty) external nonReentrant whenNotPaused {
        _buy(tx.accounts.dataAccount.key, qty);
    }

    function buyFor(
        address buyer,
        uint256 qty,
        uint256 deadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "SigExpired");

        bytes32 structHash = keccak256(abi.encode(
            BUY_TYPEHASH,
            buyer,
            qty,
            buyNonces[buyer],
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ecrecover_solana(digest, v, r, s);
        require(signer != address(0) && signer == buyer, "InvalidSignature");

        unchecked { buyNonces[buyer]++; }

        uint64 _orderId = _buy(buyer, qty);
        emit MetaPurchased(_orderId, buyer, tx.accounts.dataAccount.key);
    }

    function _buy(address buyer, uint256 qty) internal returns (uint64 orderId) {
        require(block.timestamp >= startsAt && block.timestamp <= endsAt, "SaleNotOpen");
        require(qty >= minTokens, "BelowMin");

        uint256 newWalletTotal = tokensBoughtBy[buyer] + qty;
        require(newWalletTotal <= maxTokens, "WalletCapHit");

        uint256 usdtCost = qty * pricePerToken;
        require(totalRaised + usdtCost <= hardCap, "CapExceeded");

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

        _safeTransferFrom(usdt, buyer, address(this), usdtCost);

        emit Purchased(orderId, buyer, qty, usdtCost, _maxTrueUp);
    }

    function trueUp(uint64 orderId, uint256 additional)
        external onlyOwner nonReentrant whenNotPaused
    {
        require(!refundsEnabled, "TrueUpUnavailable");
        Order storage o = orders[orderId];
        require(o.buyer != address(0), "OrderNotFound");
        require(block.timestamp <= uint256(o.timestamp) + trueUpWindow, "TrueUpWindowClosed");
        require(o.trueUpCollected + additional <= o.maxTrueUp, "TrueUpExceedsMargin");

        o.trueUpCollected   += additional;
        usdtPaidBy[o.buyer] += additional;
        totalRaised         += additional;

        _safeTransferFrom(usdt, o.buyer, address(this), additional);

        emit TrueUpCharged(orderId, o.buyer, additional);
    }

    function setCaps(uint256 _min, uint256 _max, uint256 _soft, uint256 _hard) external onlyOwner {
        require(_max >= _min && _hard >= _soft && _hard != 0, "BadConfig");
        minTokens = _min; maxTokens = _max; softCap = _soft; hardCap = _hard;
        emit CapsUpdated(_min, _max, _soft, _hard);
    }

    function setWindow(uint64 _starts, uint64 _ends) external onlyOwner {
        require(_ends > _starts, "BadConfig");
        startsAt = _starts; endsAt = _ends;
        emit WindowUpdated(_starts, _ends);
    }

    function setTreasury(address _t) external onlyOwner {
        require(_t != address(0), "AddrZero");
        treasury = _t;
        emit TreasuryUpdated(_t);
    }

    function setMargin(uint16 _marginBps, uint32 _windowSecs) external onlyOwner {
        require(_marginBps <= MAX_MARGIN_BPS, "BadConfig");
        require(_windowSecs <= MAX_TRUEUP_WINDOW, "BadConfig");
        marginBps    = _marginBps;
        trueUpWindow = _windowSecs;
        emit MarginUpdated(_marginBps, _windowSecs);
    }

    function pause()   external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function sweep() external onlyOwner {
        require(block.timestamp > endsAt, "SaleNotEnded");
        require(totalRaised >= softCap, "SoftCapMissed");
        uint256 bal = _balanceOf(usdt, address(this));
        _safeTransfer(usdt, treasury, bal);
        emit Swept(bal);
    }

    function enableRefunds() external onlyOwner {
        require(block.timestamp > endsAt, "SaleNotEnded");
        require(totalRaised < softCap, "SoftCapHit");
        refundsEnabled = true;
        emit RefundsOpened();
    }

    function refundTo(address buyer) external onlyOwner nonReentrant {
        _refund(buyer);
    }

    function batchRefund(address[] calldata buyers) external onlyOwner nonReentrant {
        require(refundsEnabled, "RefundsClosed");
        uint256 n = buyers.length;
        for (uint256 i = 0; i < n; ) {
            address b = buyers[i];
            uint256 amt = usdtPaidBy[b];
            if (amt != 0) {
                usdtPaidBy[b]      = 0;
                tokensBoughtBy[b]  = 0;
                totalRaised       -= amt;
                _safeTransfer(usdt, b, amt);
                emit Refunded(b, amt);
            }
            unchecked { i++; }
        }
    }

    function claimRefund() external nonReentrant {
        _refund(tx.accounts.dataAccount.key);
    }

    function _refund(address buyer) internal {
        require(refundsEnabled, "RefundsClosed");
        uint256 amt = usdtPaidBy[buyer];
        require(amt != 0, "NothingToRefund");

        usdtPaidBy[buyer]     = 0;
        tokensBoughtBy[buyer] = 0;
        totalRaised          -= amt;

        _safeTransfer(usdt, buyer, amt);
        emit Refunded(buyer, amt);
    }

    function isOpen() external view returns (bool) {
        return !paused
            && block.timestamp >= startsAt
            && block.timestamp <= endsAt
            && totalRaised < hardCap;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AddrZero");
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(tx.accounts.dataAccount.key == pendingOwner, "not pending");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private immutable DOMAIN_SEPARATOR;

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call{accounts: []}(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success, "transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call{accounts: []}(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        require(success, "transferFrom failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory returndata) = token.call{accounts: []}(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        require(success, "balanceOf failed");
        return abi.decode(returndata, (uint256));
    }

    function ecrecover_solana(bytes32 digest, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(digest, v, r, s));
        return address(uint160(uint256(hash)));
    }
}