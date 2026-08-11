// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title vXVO Presale
/// @notice Sells vXVO across 4 progressive-price rounds, enforces a per-wallet
///         USD cap via Chainlink ETH/USD, and uses a pull-claim distribution
///         pattern (users pay their own gas to claim purchased tokens).
contract VxvoPresale is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======================================================================
    // Storage
    // ======================================================================

    IERC20 public immutable vxvo;
    AggregatorV3Interface public immutable ethUsdFeed;

    address public ownerWallet;

    /// Per-wallet hard cap of $5,000 (8 decimals to match Chainlink format).
    uint256 public constant MAX_USD_PER_WALLET_E8 = 5_000 * 1e8;

    /// Reject Chainlink data older than this — protects against stale prices.
    uint256 public constant PRICE_FEED_MAX_AGE = 1 hours;

    struct Round {
        uint256 priceUsdE8;  // price per vXVO in USD, 8 decimals
        uint256 allocation;  // total vXVO for this round (18 decimals)
        uint256 sold;        // vXVO sold so far in this round (18 decimals)
    }

    Round[4] public rounds;
    uint8 public currentRound;

    bool public saleActive;

    /// Cumulative USD contributed per wallet (8 decimals).
    mapping(address => uint256) public usdContributedE8;

    /// vXVO claimable per wallet (18 decimals).
    mapping(address => uint256) public claimable;

    // ======================================================================
    // Events
    // ======================================================================

    event Purchased(
        address indexed user,
        uint256 ethAmount,
        uint256 usdValueE8,
        uint256 vxvoAmount,
        uint8 round
    );
    event Claimed(address indexed user, uint256 vxvoAmount);
    event RoundAdvanced(uint8 newRound);
    event SaleStatusChanged(bool active);
    event OwnerWalletUpdated(address newWallet);

    // ======================================================================
    // Constructor
    // ======================================================================

    constructor(
        address admin,
        address vxvoToken,
        address ethUsdPriceFeed,
        address ownerWallet_
    ) {
        require(admin != address(0), "admin zero");
        require(vxvoToken != address(0), "token zero");
        require(ethUsdPriceFeed != address(0), "feed zero");
        require(ownerWallet_ != address(0), "owner zero");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        vxvo = IERC20(vxvoToken);
        ethUsdFeed = AggregatorV3Interface(ethUsdPriceFeed);
        ownerWallet = ownerWallet_;

        // 4 rounds, 2B vXVO each (8B total — 2B is split off to MarketingVesting),
        // at $0.015 / $0.0225 / $0.030 / $0.0375. Max raise = $210M (if all fill).
        // Post-presale public listing target: $0.050 (not enforced on-chain).
        // Allocations use 6 decimals (vXVO): 2B vXVO = 2e9 * 1e6 base units.
        rounds[0] = Round(0.015e8, 2_000_000_000e6, 0);   // price 1_500_000 E8
        rounds[1] = Round(0.0225e8, 2_000_000_000e6, 0);  // price 2_250_000 E8
        rounds[2] = Round(0.030e8, 2_000_000_000e6, 0);   // price 3_000_000 E8
        rounds[3] = Round(0.0375e8, 2_000_000_000e6, 0);  // price 3_750_000 E8
    }

    // ======================================================================
    // External — purchase
    // ======================================================================

    function buy() external payable nonReentrant {
        require(saleActive, "sale not active");
        require(msg.value > 0, "no eth sent");
        require(currentRound < 4, "presale ended");

        uint256 ethUsdPriceE8 = getEthUsdPriceE8();

        // wei * priceE8 / 1e18 = USD with 8 decimals
        uint256 usdValueE8 = (msg.value * ethUsdPriceE8) / 1e18;
        require(usdValueE8 > 0, "amount too small");

        require(
            usdContributedE8[msg.sender] + usdValueE8 <= MAX_USD_PER_WALLET_E8,
            "exceeds $5000 cap"
        );

        Round storage r = rounds[currentRound];

        // vXVO (6 decimals) = USD-E8 * 1e6 / pricePerVxvoUsd-E8 (E8s cancel).
        uint256 vxvoAmount = (usdValueE8 * 1e6) / r.priceUsdE8;
        require(vxvoAmount > 0, "vxvo amount zero");
        require(
            r.sold + vxvoAmount <= r.allocation,
            "exceeds round allocation"
        );

        // Effects
        usdContributedE8[msg.sender] += usdValueE8;
        claimable[msg.sender] += vxvoAmount;
        r.sold += vxvoAmount;

        emit Purchased(
            msg.sender,
            msg.value,
            usdValueE8,
            vxvoAmount,
            currentRound
        );

        // Auto-advance round if filled
        if (r.sold >= r.allocation) {
            if (currentRound < 3) {
                currentRound++;
                emit RoundAdvanced(currentRound);
            } else {
                // Final round filled — end the sale
                saleActive = false;
                emit SaleStatusChanged(false);
            }
        }

        // Forward ETH to owner wallet (interactions last)
        (bool ok, ) = ownerWallet.call{value: msg.value}("");
        require(ok, "eth forward failed");
    }

    // ======================================================================
    // External — claim
    // ======================================================================

    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "nothing to claim");

        claimable[msg.sender] = 0;
        vxvo.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    // ======================================================================
    // Admin
    // ======================================================================

    function setSaleActive(bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        saleActive = active;
        emit SaleStatusChanged(active);
    }

    function setOwnerWallet(address newWallet)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newWallet != address(0), "zero address");
        ownerWallet = newWallet;
        emit OwnerWalletUpdated(newWallet);
    }

    /// Allow admin to skip ahead manually (does not skip backward).
    function advanceRound() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(currentRound < 3, "already at last round");
        currentRound++;
        emit RoundAdvanced(currentRound);
    }

    /// Recover any ERC20 left in this contract — useful for unsold vXVO after
    /// sale ends, or for mistakenly-sent tokens.
    function rescueTokens(address token, address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(to != address(0), "to zero");
        IERC20(token).safeTransfer(to, amount);
    }

    // ======================================================================
    // Views
    // ======================================================================

    function getEthUsdPriceE8() public view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = ethUsdFeed.latestRoundData();
        require(price > 0, "bad price");
        require(
            block.timestamp - updatedAt <= PRICE_FEED_MAX_AGE,
            "stale price"
        );
        return uint256(price);
    }

    function getRound(uint8 index)
        external
        view
        returns (uint256 priceUsdE8, uint256 allocation, uint256 sold)
    {
        require(index < 4, "invalid round");
        Round memory r = rounds[index];
        return (r.priceUsdE8, r.allocation, r.sold);
    }

    function getRemainingUsdCapE8(address user)
        external
        view
        returns (uint256)
    {
        uint256 contributed = usdContributedE8[user];
        if (contributed >= MAX_USD_PER_WALLET_E8) return 0;
        return MAX_USD_PER_WALLET_E8 - contributed;
    }

    /// Helper for the frontend: given an ETH amount, return what the user
    /// would receive at the current round's price.
    function previewPurchase(uint256 ethAmount)
        external
        view
        returns (uint256 usdValueE8, uint256 vxvoAmount)
    {
        if (currentRound >= 4) return (0, 0);
        uint256 ethUsdPriceE8 = getEthUsdPriceE8();
        usdValueE8 = (ethAmount * ethUsdPriceE8) / 1e18; // ETH is 18-dec
        Round memory r = rounds[currentRound];
        vxvoAmount = (usdValueE8 * 1e6) / r.priceUsdE8; // vXVO is 6-dec
    }

    // ======================================================================
    // Reject direct ETH transfers (force users through buy())
    // ======================================================================

    receive() external payable {
        revert("use buy()");
    }

    fallback() external payable {
        revert("invalid call");
    }
}
