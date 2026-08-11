// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );
}

/**
 * @title  SSCPresale
 * @notice 3-tier SSC presale. Buy with USDT or ETH (Chainlink-priced).
 *  Price     : $0.005 / SSC
 *  Hard Cap  : $6M ($600K T1 +10%, $1.8M T2 +5%, $3.6M T3 +0%)
 *  TGE       : 2026-10-01 00:00:00 UTC (hardcoded)
 *  Vesting   : 10% at TGE, 90% linear over 12 months
 *  Affiliate : L1 5%, L2 3%, L3 2% — paid in purchase currency
 */
contract SSCPresale is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    uint256 public constant PRICE_USD    = 5;        // $0.005 = 5/1000
    uint256 public constant PRICE_DENOM  = 1000;

    uint256 public constant HARD_CAP   = 6_000_000 * 1e6;
    uint256 public constant T1_USD_CAP =   600_000 * 1e6;
    uint256 public constant T2_USD_CAP = 1_800_000 * 1e6;
    uint256 public constant T3_USD_CAP = 3_600_000 * 1e6;

    // Max allocatable SSC if every tier sells out with max bonus:
    // 132M (T1 +10%) + 378M (T2 +5%) + 720M (T3) = 1.23B.
    // Must be deposited in full before sale can open.
    uint256 public constant MAX_PRESALE_SSC = 1_230_000_000 * 1e18;

    uint256 public constant T1_BONUS_BPS = 1000;     // +10%
    uint256 public constant T2_BONUS_BPS = 500;      // +5%

    uint256 public constant TGE_BPS     = 1000;      // 10% at TGE
    uint256 public constant VEST_MONTHS = 12;
    uint256 public constant MONTH       = 30 days;

    uint8   public constant TIER_DONE = 4;

    uint256 public constant AFF_L1_BPS = 500;
    uint256 public constant AFF_L2_BPS = 300;
    uint256 public constant AFF_L3_BPS = 200;

    uint256 public constant PRICE_STALE_AFTER = 2 hours;

    // 2026-10-01 00:00:00 UTC — hardcoded so buyers can verify when
    // claims open independently of owner cooperation.
    uint256 public constant TGE_TIMESTAMP = 1790812800;

    // If push exceeds this, payment falls back to pull (claimAffiliateEth)
    // so a hostile recipient cannot DoS a downline's purchase.
    uint256 public constant ETH_PUSH_GAS = 50_000;

    uint8   public constant CCY_USDT = 0;
    uint8   public constant CCY_ETH  = 1;

    IERC20                public immutable sscToken;
    IERC20                public immutable usdt;
    AggregatorV3Interface public immutable ethUsdFeed;

    bool    public saleOpen;
    uint8   public currentTier = 1;
    uint256 public minBuyUsd = 1 * 1e6;              // default $1, owner-tunable

    uint256 public t1Raised;
    uint256 public t2Raised;
    uint256 public t3Raised;
    uint256 public totalRaisedUsd;
    uint256 public totalUsdtIn;
    uint256 public totalEthIn;
    uint256 public totalSscAllocated;
    uint256 public totalSscOwed;
    uint256 public totalSscDeposited;

    mapping(address => address) public referrer;

    struct AffiliateRecord {
        address buyer;
        uint256 amount;
        uint8   currency;
        uint8   level;
        uint256 at;
    }
    mapping(address => AffiliateRecord[]) private _affiliateHistory;

    mapping(address => uint256) public affiliateEarnedUsdt;
    mapping(address => uint256) public affiliateEarnedEth;
    mapping(address => uint256) public affiliateCount;

    mapping(address => uint256) public affiliateEthClaimable;
    uint256 public affiliateEthClaimablePool;

    uint256 public totalAffiliatePaidUsdt;
    uint256 public totalAffiliatePaidEth;

    address[] public affiliates;
    mapping(address => bool) private _isAffiliate;

    struct Position {
        uint256 usdCommitted;
        uint256 usdtSpent;
        uint256 ethSpent;
        uint256 sscBase;
        uint256 sscBonus;
        uint256 sscTotal;
        uint256 claimed;
        uint256 firstPurchase;
    }
    mapping(address => Position) public positions;
    address[] public buyers;

    event SaleOpened();
    event SaleClosed();
    event TierAdvanced(uint8 indexed from, uint8 indexed to);
    event Purchased(
        address indexed buyer,
        uint8   currency,
        uint256 paidAmount,
        uint256 usdValue,
        uint256 sscBase,
        uint256 sscBonus,
        address indexed ref,
        uint256 timestamp
    );
    event AffiliateRewarded(
        address indexed affiliate,
        address indexed buyer,
        uint8   currency,
        uint8   level,
        uint256 amount
    );
    event SscDeposited(uint256 amount);
    event MinBuyUpdated(uint256 oldMin, uint256 newMin);
    event Claimed(address indexed buyer, uint256 amount, uint256 timestamp);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event EthWithdrawn(address indexed to, uint256 amount);
    event AffiliateEthAccrued(address indexed affiliate, address indexed buyer, uint8 level, uint256 amount);
    event AffiliateEthClaimed(address indexed affiliate, uint256 amount);

    constructor(
        address _sscToken,
        address _usdt,
        address _ethUsdFeed,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_sscToken   != address(0), "zero sscToken");
        require(_usdt       != address(0), "zero usdt");
        require(_ethUsdFeed != address(0), "zero ethUsdFeed");
        sscToken   = IERC20(_sscToken);
        usdt       = IERC20(_usdt);
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
    }

    function buyWithUSDT(uint256 usdAmount, address ref)
        external
        nonReentrant
        whenNotPaused
    {
        _preBuyChecks(usdAmount);

        usdt.safeTransferFrom(msg.sender, address(this), usdAmount);

        _setReferrerOnce(ref);
        _processBuy(msg.sender, usdAmount, usdAmount, 0);
        _distributeAffiliateUSDT(msg.sender, usdAmount);

        totalUsdtIn += usdAmount;
    }

    /// @param minUsdValue Slippage floor in USDT 6dec. Pass 0 to disable.
    function buyWithETH(address ref, uint256 minUsdValue)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(msg.value > 0, "no ETH sent");

        uint256 usdValue = _ethToUsd(msg.value);
        require(usdValue >= minUsdValue, "slippage: USD below min");
        _preBuyChecks(usdValue);

        _setReferrerOnce(ref);
        _processBuy(msg.sender, usdValue, 0, msg.value);
        _distributeAffiliateETH(msg.sender, msg.value);

        totalEthIn += msg.value;
    }

    function _preBuyChecks(uint256 usdAmount) internal view {
        require(saleOpen,                              "sale not open");
        require(block.timestamp < TGE_TIMESTAMP,       "TGE reached, sale ended");
        require(currentTier < TIER_DONE,               "presale sold out");
        require(usdAmount >= minBuyUsd,                "below min buy");
        require(totalRaisedUsd + usdAmount <= HARD_CAP,"exceeds hard cap");
    }

    function _setReferrerOnce(address ref) internal {
        if (referrer[msg.sender] == address(0)
                && ref != address(0)
                && ref != msg.sender
                && !_wouldCreateCycle(ref)) {
            referrer[msg.sender] = ref;
        }
    }

    function _wouldCreateCycle(address newRef) internal view returns (bool) {
        address cur = newRef;
        for (uint8 i = 0; i < 3; i++) {
            if (cur == address(0)) return false;
            if (cur == msg.sender) return true;
            cur = referrer[cur];
        }
        return false;
    }

    function _processBuy(
        address buyer,
        uint256 usdAmount,
        uint256 usdtSpent,
        uint256 ethSpent
    ) internal {
        uint256 remaining  = usdAmount;
        uint256 totalBase  = 0;
        uint256 totalBonus = 0;

        while (remaining > 0 && currentTier < TIER_DONE) {
            uint256 tierLeft = _tierCap(currentTier) - _tierRaised(currentTier);

            if (tierLeft == 0) {
                _advanceTier();
                continue;
            }

            uint256 fill = remaining < tierLeft ? remaining : tierLeft;

            // fill(6dec) * 1000/5 * 1e12 -> SSC(18dec)
            uint256 base  = fill * PRICE_DENOM / PRICE_USD * 1e12;
            uint256 bonus = base * _tierBonusBps(currentTier) / 10000;

            totalBase  += base;
            totalBonus += bonus;

            if      (currentTier == 1) t1Raised += fill;
            else if (currentTier == 2) t2Raised += fill;
            else                       t3Raised += fill;

            remaining -= fill;

            if (fill == tierLeft) _advanceTier();
        }

        require(remaining == 0, "purchase exceeds available supply");

        uint256 sscTotal = totalBase + totalBonus;

        if (positions[buyer].usdCommitted == 0) {
            buyers.push(buyer);
            positions[buyer].firstPurchase = block.timestamp;
        }

        positions[buyer].usdCommitted += usdAmount;
        positions[buyer].usdtSpent    += usdtSpent;
        positions[buyer].ethSpent     += ethSpent;
        positions[buyer].sscBase      += totalBase;
        positions[buyer].sscBonus     += totalBonus;
        positions[buyer].sscTotal     += sscTotal;

        totalRaisedUsd    += usdAmount;
        totalSscAllocated += sscTotal;
        totalSscOwed      += sscTotal;

        emit Purchased(
            buyer,
            ethSpent > 0 ? CCY_ETH : CCY_USDT,
            ethSpent > 0 ? ethSpent : usdtSpent,
            usdAmount,
            totalBase,
            totalBonus,
            referrer[buyer],
            block.timestamp
        );
    }

    function _distributeAffiliateUSDT(address buyer, uint256 usdAmount) internal {
        address l1 = referrer[buyer];
        if (l1 == address(0)) return;

        uint256 r1 = usdAmount * AFF_L1_BPS / 10000;
        _recordAffiliateUSDT(l1, buyer, r1, 1);
        usdt.safeTransfer(l1, r1);
        emit AffiliateRewarded(l1, buyer, CCY_USDT, 1, r1);

        address l2 = referrer[l1];
        if (l2 == address(0)) return;

        uint256 r2 = usdAmount * AFF_L2_BPS / 10000;
        _recordAffiliateUSDT(l2, buyer, r2, 2);
        usdt.safeTransfer(l2, r2);
        emit AffiliateRewarded(l2, buyer, CCY_USDT, 2, r2);

        address l3 = referrer[l2];
        if (l3 == address(0)) return;

        uint256 r3 = usdAmount * AFF_L3_BPS / 10000;
        _recordAffiliateUSDT(l3, buyer, r3, 3);
        usdt.safeTransfer(l3, r3);
        emit AffiliateRewarded(l3, buyer, CCY_USDT, 3, r3);
    }

    function _recordAffiliateUSDT(address aff, address buyer, uint256 amount, uint8 level) internal {
        _affiliateHistory[aff].push(AffiliateRecord({
            buyer: buyer, amount: amount, currency: CCY_USDT, level: level, at: block.timestamp
        }));
        affiliateEarnedUsdt[aff] += amount;
        affiliateCount[aff]      += 1;
        totalAffiliatePaidUsdt   += amount;
        if (!_isAffiliate[aff]) { _isAffiliate[aff] = true; affiliates.push(aff); }
    }

    function _distributeAffiliateETH(address buyer, uint256 ethAmount) internal {
        address l1 = referrer[buyer];
        if (l1 == address(0)) return;
        _payAffiliateEth(l1, buyer, ethAmount * AFF_L1_BPS / 10000, 1);

        address l2 = referrer[l1];
        if (l2 == address(0)) return;
        _payAffiliateEth(l2, buyer, ethAmount * AFF_L2_BPS / 10000, 2);

        address l3 = referrer[l2];
        if (l3 == address(0)) return;
        _payAffiliateEth(l3, buyer, ethAmount * AFF_L3_BPS / 10000, 3);
    }

    // Records stats first, then attempts push. If push fails, amount is
    // accrued to claimable — referrer cannot DoS downline's purchase.
    function _payAffiliateEth(address aff, address buyer, uint256 amount, uint8 level) internal {
        _recordAffiliateETH(aff, buyer, amount, level);

        (bool ok, ) = payable(aff).call{value: amount, gas: ETH_PUSH_GAS}("");
        if (ok) {
            emit AffiliateRewarded(aff, buyer, CCY_ETH, level, amount);
        } else {
            affiliateEthClaimable[aff] += amount;
            affiliateEthClaimablePool  += amount;
            emit AffiliateEthAccrued(aff, buyer, level, amount);
        }
    }

    function _recordAffiliateETH(address aff, address buyer, uint256 amount, uint8 level) internal {
        _affiliateHistory[aff].push(AffiliateRecord({
            buyer: buyer, amount: amount, currency: CCY_ETH, level: level, at: block.timestamp
        }));
        affiliateEarnedEth[aff] += amount;
        affiliateCount[aff]     += 1;
        totalAffiliatePaidEth   += amount;
        if (!_isAffiliate[aff]) { _isAffiliate[aff] = true; affiliates.push(aff); }
    }

    function claimAffiliateEth() external nonReentrant {
        uint256 amount = affiliateEthClaimable[msg.sender];
        require(amount > 0, "nothing to claim");

        affiliateEthClaimable[msg.sender]  = 0;
        affiliateEthClaimablePool         -= amount;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH claim failed");
        emit AffiliateEthClaimed(msg.sender, amount);
    }

    function _sendEth(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "ETH transfer failed");
    }

    function _advanceTier() internal {
        uint8 prev = currentTier;
        if (currentTier < 3) {
            currentTier++;
            emit TierAdvanced(prev, currentTier);
        } else {
            currentTier = TIER_DONE;
            saleOpen    = false;
            emit TierAdvanced(prev, TIER_DONE);
            emit SaleClosed();
        }
    }

    /// @dev Returns wei → USD in 6 decimals (USDT convention).
    function _ethToUsd(uint256 weiAmount) internal view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = ethUsdFeed.latestRoundData();
        require(price > 0,                                       "bad oracle price");
        require(block.timestamp - updatedAt <= PRICE_STALE_AFTER,"stale oracle price");

        uint8 feedDecimals = ethUsdFeed.decimals();
        // wei * price(feedDec) / 10**feedDec → 18dec; / 1e12 → 6dec
        return weiAmount * uint256(price) / (10 ** feedDecimals) / 1e12;
    }

    function quoteEth(uint256 weiAmount) external view returns (uint256 usd6) {
        return _ethToUsd(weiAmount);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function setMinBuy(uint256 newMin) external onlyOwner {
        require(newMin > 0, "zero min");
        emit MinBuyUpdated(minBuyUsd, newMin);
        minBuyUsd = newMin;
    }

    function setSaleOpen(bool open) external onlyOwner {
        if (open == saleOpen) return;
        if (open) {
            // Uses balanceOf (not totalSscDeposited) so re-opening after
            // a surplus withdrawal requires re-deposit.
            require(
                sscToken.balanceOf(address(this)) >= MAX_PRESALE_SSC,
                "SSC backing insufficient"
            );
        }
        saleOpen = open;
        if (open) emit SaleOpened();
        else      emit SaleClosed();
    }

    function depositSsc(uint256 amount) external onlyOwner {
        require(amount > 0, "zero amount");
        totalSscDeposited += amount;
        sscToken.safeTransferFrom(msg.sender, address(this), amount);
        emit SscDeposited(amount);
    }

    /// @notice SSC withdrawal blocked while saleOpen. After close, only
    ///         surplus (balance - totalSscOwed) is withdrawable.
    function withdrawFunds(address token, address to) external onlyOwner {
        require(to != address(0), "zero address");

        uint256 bal = IERC20(token).balanceOf(address(this));

        if (token == address(sscToken)) {
            require(!saleOpen, "sale still open");
            require(bal > totalSscOwed, "no surplus SSC");
            bal = bal - totalSscOwed;
        }

        require(bal > 0, "no token balance");
        IERC20(token).safeTransfer(to, bal);
        emit FundsWithdrawn(token, to, bal);
    }

    /// @dev Reserves affiliateEthClaimablePool for pull-claims.
    function withdrawETH(address payable to) external onlyOwner {
        require(to != address(0), "zero address");
        uint256 bal      = address(this).balance;
        uint256 reserved = affiliateEthClaimablePool;
        require(bal > reserved, "no surplus ETH");
        uint256 amount = bal - reserved;
        _sendEth(to, amount);
        emit EthWithdrawn(to, amount);
    }

    function claim() external nonReentrant {
        require(totalSscDeposited > 0,              "SSC not deposited yet");
        require(block.timestamp >= TGE_TIMESTAMP,   "TGE not reached yet");

        uint256 amount = claimable(msg.sender);
        require(amount > 0, "nothing to claim");

        positions[msg.sender].claimed += amount;
        totalSscOwed                  -= amount;

        sscToken.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount, block.timestamp);
    }

    function claimable(address buyer) public view returns (uint256) {
        Position memory p = positions[buyer];
        if (p.sscTotal == 0)                     return 0;
        if (block.timestamp < TGE_TIMESTAMP)     return 0;

        uint256 tgeAmt  = p.sscTotal * TGE_BPS / 10000;
        uint256 vestAmt = p.sscTotal - tgeAmt;

        uint256 monthsPassed = (block.timestamp - TGE_TIMESTAMP) / MONTH;

        uint256 vested = monthsPassed >= VEST_MONTHS
            ? p.sscTotal
            : tgeAmt + (vestAmt * monthsPassed / VEST_MONTHS);

        return vested > p.claimed ? vested - p.claimed : 0;
    }

    function buyerStatus(address buyer) external view returns (
        uint256 usdCommitted,
        uint256 usdtSpent,
        uint256 ethSpent,
        uint256 sscBase,
        uint256 sscBonus,
        uint256 sscTotal,
        uint256 sscClaimed,
        uint256 sscClaimable,
        uint256 sscLocked,
        uint256 vestMonthsElapsed
    ) {
        Position memory p = positions[buyer];
        usdCommitted = p.usdCommitted;
        usdtSpent    = p.usdtSpent;
        ethSpent     = p.ethSpent;
        sscBase      = p.sscBase;
        sscBonus     = p.sscBonus;
        sscTotal     = p.sscTotal;
        sscClaimed   = p.claimed;
        sscClaimable = claimable(buyer);
        sscLocked    = p.sscTotal - p.claimed - sscClaimable;
        if (block.timestamp >= TGE_TIMESTAMP) {
            uint256 m = (block.timestamp - TGE_TIMESTAMP) / MONTH;
            vestMonthsElapsed = m > VEST_MONTHS ? VEST_MONTHS : m;
        }
    }

    function currentTierInfo() external view returns (
        uint8   tier,
        uint256 raised,
        uint256 cap,
        uint256 remaining,
        uint256 minBuy,
        uint256 bonusBps
    ) {
        if (currentTier >= TIER_DONE) return (TIER_DONE, 0, 0, 0, 0, 0);
        tier      = currentTier;
        raised    = _tierRaised(currentTier);
        cap       = _tierCap(currentTier);
        remaining = cap - raised;
        minBuy    = minBuyUsd;
        bonusBps  = _tierBonusBps(currentTier);
    }

    function allTierProgress() external view returns (
        uint256 t1r, uint256 t1c,
        uint256 t2r, uint256 t2c,
        uint256 t3r, uint256 t3c
    ) {
        return (t1Raised, T1_USD_CAP, t2Raised, T2_USD_CAP, t3Raised, T3_USD_CAP);
    }

    function getUplines(address buyer) external view returns (address l1, address l2, address l3) {
        l1 = referrer[buyer];
        if (l1 != address(0)) l2 = referrer[l1];
        if (l2 != address(0)) l3 = referrer[l2];
    }

    function affiliateHistoryCount(address aff) external view returns (uint256) {
        return _affiliateHistory[aff].length;
    }

    function affiliateHistoryPage(address aff, uint256 offset, uint256 limit)
        external view returns (AffiliateRecord[] memory page, uint256 total)
    {
        AffiliateRecord[] storage all = _affiliateHistory[aff];
        total = all.length;
        if (offset >= total || limit == 0) return (new AffiliateRecord[](0), total);
        uint256 end  = offset + limit > total ? total : offset + limit;
        uint256 size = end - offset;
        page = new AffiliateRecord[](size);
        for (uint256 i = 0; i < size; i++) page[i] = all[offset + i];
    }

    function affiliateSummary(address aff) external view returns (
        uint256 earnedUsdt,
        uint256 earnedEth,
        uint256 countTotal
    ) {
        earnedUsdt = affiliateEarnedUsdt[aff];
        earnedEth  = affiliateEarnedEth[aff];
        countTotal = affiliateCount[aff];
    }

    struct BuyerExport {
        address wallet;
        uint256 usdCommitted;
        uint256 usdtSpent;
        uint256 ethSpent;
        uint256 sscBase;
        uint256 sscBonus;
        uint256 sscTotal;
        uint256 claimed;
        uint256 firstPurchase;
    }

    function exportBuyersPage(uint256 offset, uint256 limit)
        external view returns (BuyerExport[] memory page, uint256 total)
    {
        total = buyers.length;
        if (offset >= total || limit == 0) return (new BuyerExport[](0), total);
        uint256 end  = offset + limit > total ? total : offset + limit;
        uint256 size = end - offset;
        page = new BuyerExport[](size);
        for (uint256 i = 0; i < size; i++) {
            address w = buyers[offset + i];
            Position memory p = positions[w];
            page[i] = BuyerExport({
                wallet:        w,
                usdCommitted:  p.usdCommitted,
                usdtSpent:     p.usdtSpent,
                ethSpent:      p.ethSpent,
                sscBase:       p.sscBase,
                sscBonus:      p.sscBonus,
                sscTotal:      p.sscTotal,
                claimed:       p.claimed,
                firstPurchase: p.firstPurchase
            });
        }
    }

    function totalBuyers()     external view returns (uint256) { return buyers.length; }
    function totalTokensSold() external view returns (uint256) { return totalSscAllocated; }
    function remainingCap()    external view returns (uint256) { return HARD_CAP - totalRaisedUsd; }

    function depositShortfall() external view returns (uint256) {
        if (totalSscAllocated <= totalSscDeposited) return 0;
        return totalSscAllocated - totalSscDeposited;
    }

    function getPosition(address buyer) external view returns (Position memory) {
        return positions[buyer];
    }

    function _tierCap(uint8 tier) internal pure returns (uint256) {
        if (tier == 1) return T1_USD_CAP;
        if (tier == 2) return T2_USD_CAP;
        return T3_USD_CAP;
    }

    function _tierRaised(uint8 tier) internal view returns (uint256) {
        if (tier == 1) return t1Raised;
        if (tier == 2) return t2Raised;
        return t3Raised;
    }

    function _tierBonusBps(uint8 tier) internal pure returns (uint256) {
        if (tier == 1) return T1_BONUS_BPS;
        if (tier == 2) return T2_BONUS_BPS;
        return 0;
    }

    receive() external payable {
        revert("use buyWithETH");
    }
}
