// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "./interfaces/IArtvybeMarketplace.sol";

contract ArtvybeMarketplace is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    UUPSUpgradeable,
    IArtvybeMarketplace
{
    using SafeERC20 for IERC20;

    // -----------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------

    /// @notice Hard ceiling for platform / creator / royalty fees in bps.
    uint96 public constant MAX_FEE_BPS = 1000; // 10%
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public constant MIN_BID_INCREMENT = 0.01 ether;
    uint256 public constant MIN_OFFER_DURATION = 1 hours;
    uint256 public constant MAX_OFFER_DURATION = 30 days;
    uint256 public constant REFUND_PUSH_GAS = 30_000;

    /// @notice Hard cap on items per `batchBuy` call. Picked so the
    ///         worst-case loop (heavy royalty + ERC721 hooks per item)
    ///         still fits comfortably within a single block's gas limit
    ///         on every chain we target. If a basket exceeds this the
    ///         frontend chunks into multiple txs.
    uint256 public constant MAX_BATCH_BUY = 50;

    /// @dev Skip-reason tags emitted via `BatchItemSkipped`. Short ASCII
    ///      so they're cheap to compare and human-readable in explorers.
    bytes32 private constant SKIP_LISTING_INACTIVE  = "LISTING_INACTIVE";
    bytes32 private constant SKIP_NOT_FIXED_PRICE   = "NOT_FIXED_PRICE";
    bytes32 private constant SKIP_PRICE_MISMATCH    = "PRICE_MISMATCH";
    bytes32 private constant SKIP_CURRENCY_MISMATCH = "CURRENCY_MISMATCH";
    bytes32 private constant SKIP_SELF_PURCHASE     = "SELF_PURCHASE";

    /// @dev Sentinel used in `totalOwed` to track native-token escrow.
    address private constant NATIVE = address(0);

    // -----------------------------------------------------------------
    // Storage (DO NOT REORDER existing slots — proxy storage layout)
    // -----------------------------------------------------------------

    uint96 public platformFeeBps;
    address public platformTreasury;
    address public admin;

    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => mapping(address => Offer))) public offers; // nftContract => tokenId => offerer => Offer
    mapping(address => mapping(uint256 => address[])) public offerers; // nftContract => tokenId => offerer addresses

    /// @dev Marketplace-enforced creator earnings for imported / external collections.
    struct CollectionRoyaltyConfig {
        address receiver;
        uint96 bps;
        bool enabled;
    }

    mapping(address => CollectionRoyaltyConfig) public collectionRoyalties;
    mapping(address => address) public collectionRoyaltyAdmin;

    // ----- NEW IN THIS UPGRADE (appended before __gap) -----

    /// @notice Total funds the contract is obligated to release to users
    ///         (active bids + active offers + uncollected pull refunds).
    ///         The contract balance must always be >= this; recovery
    ///         functions can only move the excess.
    mapping(address => uint256) public totalOwed; // currency => amount

    /// @notice Pull-payment ledger. When a push refund fails (e.g. the
    ///         recipient is a contract that reverts on receive) the amount
    ///         is credited here and the user must call `withdrawPendingRefund`.
    mapping(address => mapping(address => uint256)) public pendingRefunds; // currency => user => amount

    /**
     * @notice Per-currency payment configuration.
     *
     *         `allowed`           — whether new listings / offers can be
     *                               denominated in this currency. Native
     *                               (`address(0)`) is implicitly allowed
     *                               regardless of this flag.
     *         `minBidIncrement`   — minimum delta over the current highest
     *                               bid for an auction in this currency,
     *                               expressed in the currency's atomic
     *                               units. Setting this per-currency is
     *                               critical because e.g. USDC on Ethereum
     *                               is 6 decimals but USDC on BSC is 18
     *                               decimals; a uniform "0.01 ether"
     *                               increment is broken on chains with
     *                               low-decimal payment tokens.
     */
    struct PaymentCurrencyConfig {
        bool allowed;
        uint256 minBidIncrement;
    }

    mapping(address => PaymentCurrencyConfig) public paymentCurrencies;

    // -----------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------

    error ListingNotFound();
    error ListingNotActive();
    error NotListingOwner();
    error InvalidPrice();
    error InvalidDuration();
    error InsufficientBid();
    error AuctionNotEnded();
    error AuctionAlreadyFinalized();
    error TransferFailed();
    error InvalidParameters();
    error InvalidPaymentCurrency();
    error InsufficientAllowance();
    error OfferNotFound();
    error OfferNotActive();
    error NotOfferOwner();
    error OfferExpired();
    error NotNFTOwner();
    error OfferAlreadyExists();
    error NotAdmin();
    error NotRoyaltyAdmin();

    // NEW
    error NotBidder();
    error SelfPurchase();
    error FeeOnTransferUnsupported();
    error NothingToRecover();
    error NoPendingRefund();
    error OfferNotExpired();
    error CurrencyNotAllowed();

    // batchBuy
    error BatchEmpty();
    error BatchTooLarge();
    error WrongNativeAmount();
    error BatchStrictFailure();

    // -----------------------------------------------------------------
    // Events not in the interface
    // -----------------------------------------------------------------

    event RefundCredited(address indexed user, address indexed currency, uint256 amount);
    event RefundWithdrawn(address indexed user, address indexed currency, uint256 amount);
    event CollectionRoyaltyAdminCleared(address indexed collection);
    // `PaymentCurrencyConfigured` is declared on the IArtvybeMarketplace
    // interface and inherited from there; do NOT re-declare here.

    // -----------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != admin && msg.sender != owner()) revert NotAdmin();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _platformTreasury, address _owner) public initializer {
        if (_platformTreasury == address(0)) revert InvalidParameters();
        if (_owner == address(0)) revert InvalidParameters();
        __Ownable_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC721Holder_init();
        __UUPSUpgradeable_init();
        platformTreasury = _platformTreasury;
        platformFeeBps = 200; // Default 2%
        admin = _owner;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // -----------------------------------------------------------------
    // Escrow accounting + pull-payment refund ledger
    // -----------------------------------------------------------------

    /**
     * @dev Try to push `amount` of `currency` to `user`. On failure, credit
     *      the pull-refund ledger so a single bad recipient can never DoS
     *      a multi-recipient settlement (auction finalize, accept offer,
     *      cancel listing, top-bidder eviction, ...).
     *
     *      `totalOwed[currency]` is debited only when funds actually leave
     *      the contract — failed pushes keep the funds escrowed.
     */
    function _safeRefund(address user, address currency, uint256 amount) internal {
        if (amount == 0) return;
        bool ok = _attemptPush(user, currency, amount);
        if (ok) {
            totalOwed[currency] -= amount;
        } else {
            pendingRefunds[currency][user] += amount;
            emit RefundCredited(user, currency, amount);
        }
    }

    /**
     * @dev Push `amount` of `currency` to `user`, gas-capped for native to
     *      block grief loops. Returns true on success without reverting.
     */
    // The `user` here is always the original depositor of `amount`
    // (bidder/seller/offerer/treasury) — never an arbitrary attacker-chosen
    // address. Slither flags it because it can't statically prove that.
    // slither-disable-next-line arbitrary-send-eth
    function _attemptPush(address user, address currency, uint256 amount) internal returns (bool) {
        if (currency == NATIVE) {
            (bool nativeOk, ) = user.call{value: amount, gas: REFUND_PUSH_GAS}("");
            return nativeOk;
        }
        (bool callOk, bytes memory data) = currency.call(
            abi.encodeWithSelector(IERC20.transfer.selector, user, amount)
        );
        if (!callOk) return false;
        if (data.length == 0) return true; // non-standard tokens that don't return bool
        return abi.decode(data, (bool));
    }

    /**
     * @dev Required-success counterpart to `_safeRefund`. Used for paying
     *      the platform treasury where we cannot tolerate the recipient
     *      bouncing the call (it would block all sales). Treasury is owner-
     *      controlled so this constraint is acceptable.
     */
    function _payRequired(address to, address currency, uint256 amount) internal {
        if (amount == 0) return;
        if (currency == NATIVE) {
            (bool ok, ) = to.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(currency).safeTransfer(to, amount);
        }
        totalOwed[currency] -= amount;
    }

    /**
     * @dev Pull a refund credited via the pendingRefunds ledger.
     *      Intentionally NOT gated by `whenNotPaused` — funds owed to users
     *      must always be reachable.
     */
    function withdrawPendingRefund(address currency) external nonReentrant {
        uint256 amount = pendingRefunds[currency][msg.sender];
        if (amount == 0) revert NoPendingRefund();
        pendingRefunds[currency][msg.sender] = 0;
        totalOwed[currency] -= amount;
        if (currency == NATIVE) {
            (bool ok, ) = msg.sender.call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(currency).safeTransfer(msg.sender, amount);
        }
        emit RefundWithdrawn(msg.sender, currency, amount);
    }

    function getPendingRefund(address currency, address user) external view returns (uint256) {
        return pendingRefunds[currency][user];
    }

    // -----------------------------------------------------------------
    // Payment currency registry
    // -----------------------------------------------------------------

    /**
     * @notice Allow or disallow `currency` as a payment medium for NEW
     *         listings / offers, and (re)configure its minimum auction bid
     *         increment.
     *
     *         Existing listings / offers / bids in this currency are NOT
     *         affected by disabling — they can still be cancelled,
     *         finalized, or accepted. This is by design so the admin can
     *         "soft drain" a currency without trapping in-flight funds.
     *
     *         Native (`address(0)`) is always allowed regardless of the
     *         stored `allowed` flag; however the stored `minBidIncrement`
     *         IS respected for native, allowing chains with cheap native
     *         tokens (e.g. MATIC) to bump the default. If unset, native
     *         falls back to the `MIN_BID_INCREMENT` constant.
     *
     *         For ERC20s, `minBidIncrement` must be > 0 when allowed.
     *         Decimals are NOT cached — the admin sets the increment
     *         directly in the currency's atomic units.
     */
    function setPaymentCurrency(
        address currency,
        bool allowed,
        uint256 minBidIncrement
    ) external onlyOwner {
        if (allowed && minBidIncrement == 0) revert InvalidParameters();
        paymentCurrencies[currency] = PaymentCurrencyConfig({
            allowed: allowed,
            minBidIncrement: minBidIncrement
        });
        emit PaymentCurrencyConfigured(currency, allowed, minBidIncrement);
    }

    /// @notice Effective minimum bid increment for `currency` (native falls
    ///         back to the `MIN_BID_INCREMENT` constant if not configured).
    function minBidIncrementFor(address currency) public view returns (uint256) {
        uint256 configured = paymentCurrencies[currency].minBidIncrement;
        if (configured > 0) return configured;
        if (currency == NATIVE) return MIN_BID_INCREMENT;
        return 0; // unreachable for vetted listings (allowlist enforced at list-time)
    }

    function _assertCurrencyAllowed(address currency) internal view {
        if (currency == NATIVE) return; // native always allowed
        if (!paymentCurrencies[currency].allowed) revert CurrencyNotAllowed();
    }

    /**
     * @dev Pull `claimed` of `currency` from `msg.sender` into this contract.
     *      Rejects fee-on-transfer / rebasing tokens by requiring the
     *      observed delta to equal the claimed amount.
     */
    // The before/after balance pattern is intentional and protected by
    // nonReentrant on every caller: a malicious token could only "lie"
    // about the delta against itself, which we already reject here.
    // slither-disable-next-line reentrancy-balance
    function _pullPayment(address currency, uint256 claimed) internal {
        if (currency == NATIVE) {
            if (msg.value != claimed) revert InvalidPrice();
            totalOwed[NATIVE] += claimed;
            return;
        }
        if (msg.value > 0) revert InvalidPrice();
        IERC20 token = IERC20(currency);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), claimed);
        uint256 received = token.balanceOf(address(this)) - before;
        if (received != claimed) revert FeeOnTransferUnsupported();
        totalOwed[currency] += claimed;
    }

    // -----------------------------------------------------------------
    // Top-5 bidder bookkeeping
    // -----------------------------------------------------------------

    /**
     * @dev Add or update a bidder in the top 5 list.
     * @return success True if bidder was added/updated, false if bid was too low
     * @return refundBidder Address of bidder kicked out of top 5 (zero if none)
     * @return refundAmount Amount owed to the kicked bidder (zero if none)
     */
    function _addOrUpdateBidder(Listing storage listing, address bidder, uint256 bidAmount)
        internal
        returns (bool success, address refundBidder, uint256 refundAmount)
    {
        int256 existingIndex = _findBidderIndex(listing, bidder);

        if (existingIndex >= 0) {
            uint256 current = listing.topBidders[uint256(existingIndex)].bidAmount;
            // Explicit guard: never accept a bid that doesn't strictly
            // improve on the bidder's own previous bid.
            if (bidAmount <= current) {
                return (false, address(0), 0);
            }
            listing.topBidders[uint256(existingIndex)].bidAmount = bidAmount;
            success = true;
        } else {
            if (listing.bidderCount < 5) {
                listing.topBidders[listing.bidderCount] = Bidder(bidder, bidAmount);
                listing.bidderCount++;
                success = true;
            } else {
                if (bidAmount > listing.topBidders[4].bidAmount) {
                    refundBidder = listing.topBidders[4].bidder;
                    refundAmount = listing.topBidders[4].bidAmount;
                    listing.topBidders[4] = Bidder(bidder, bidAmount);
                    success = true;
                }
            }
        }

        if (success) {
            _sortBidders(listing);
        }
    }

    function _removeBidder(Listing storage listing, address bidder) internal {
        int256 index = _findBidderIndex(listing, bidder);
        if (index < 0) return;

        uint256 bidderIndex = uint256(index);
        for (uint256 i = bidderIndex; i < listing.bidderCount - 1; i++) {
            listing.topBidders[i] = listing.topBidders[i + 1];
        }
        listing.topBidders[listing.bidderCount - 1] = Bidder(address(0), 0);
        listing.bidderCount--;
    }

    function _findBidderIndex(Listing storage listing, address bidder) internal view returns (int256) {
        for (uint256 i = 0; i < listing.bidderCount; i++) {
            if (listing.topBidders[i].bidder == bidder) {
                return int256(i);
            }
        }
        return -1;
    }

    function _sortBidders(Listing storage listing) internal {
        for (uint256 i = 0; i + 1 < listing.bidderCount; i++) {
            for (uint256 j = 0; j + 1 < listing.bidderCount - i; j++) {
                if (listing.topBidders[j].bidAmount < listing.topBidders[j + 1].bidAmount) {
                    Bidder memory temp = listing.topBidders[j];
                    listing.topBidders[j] = listing.topBidders[j + 1];
                    listing.topBidders[j + 1] = temp;
                }
            }
        }
    }

    function _getHighestBid(Listing storage listing) internal view returns (uint256) {
        if (listing.bidderCount == 0) return 0;
        return listing.topBidders[0].bidAmount;
    }

    function _getHighestBidder(Listing storage listing) internal view returns (address) {
        if (listing.bidderCount == 0) return address(0);
        return listing.topBidders[0].bidder;
    }

    /// @dev Refund every bidder via the pull-safe path. CEI: snapshot the
    ///      top-5 to memory, clear contract state, then issue refunds.
    function _refundAllBidders(Listing storage listing) internal {
        uint256 count = listing.bidderCount;
        Bidder[5] memory snapshot = listing.topBidders;
        address currency = listing.paymentCurrency;

        // Effects: clear before any external call.
        for (uint256 i = 0; i < count; i++) {
            listing.topBidders[i] = Bidder(address(0), 0);
        }
        listing.bidderCount = 0;

        // Interactions.
        for (uint256 i = 0; i < count; i++) {
            Bidder memory b = snapshot[i];
            if (b.bidder != address(0) && b.bidAmount > 0) {
                _safeRefund(b.bidder, currency, b.bidAmount);
            }
        }
    }

    // -----------------------------------------------------------------
    // Listings
    // -----------------------------------------------------------------

    function listFixedPrice(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address paymentCurrency
    ) external whenNotPaused nonReentrant {
        if (price == 0) revert InvalidPrice();
        if (listings[nftContract][tokenId].active) revert InvalidParameters();
        _assertCurrencyAllowed(paymentCurrency);

        // CEI: write the listing BEFORE pulling the NFT in. If the
        // transfer reverts the entire tx unwinds; if it succeeds the
        // listing is already in place and a malicious NFT contract's
        // callback cannot observe a "transferred but unlisted" state.
        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            listingType: ListingType.FixedPrice,
            price: price,
            paymentCurrency: paymentCurrency,
            startTime: block.timestamp,
            endTime: 0,
            topBidders: [Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0)],
            bidderCount: 0,
            active: true
        });

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        emit FixedPriceListed(msg.sender, nftContract, tokenId, price, paymentCurrency);
    }

    function listAuction(
        address nftContract,
        uint256 tokenId,
        uint256 reservePrice,
        address paymentCurrency,
        uint256 duration
    ) external whenNotPaused nonReentrant {
        if (reservePrice == 0) revert InvalidPrice();
        if (duration < MIN_AUCTION_DURATION) revert InvalidDuration();
        if (listings[nftContract][tokenId].active) revert InvalidParameters();
        _assertCurrencyAllowed(paymentCurrency);

        // CEI: write listing BEFORE pulling the NFT in. See listFixedPrice.
        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            listingType: ListingType.EnglishAuction,
            price: reservePrice,
            paymentCurrency: paymentCurrency,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            topBidders: [Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0), Bidder(address(0), 0)],
            bidderCount: 0,
            active: true
        });

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        emit AuctionListed(msg.sender, nftContract, tokenId, reservePrice, paymentCurrency, block.timestamp + duration);
    }

    function buyFixed(address nftContract, uint256 tokenId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[nftContract][tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.listingType != ListingType.FixedPrice) revert ListingNotFound();
        if (msg.sender == listing.seller) revert SelfPurchase();

        address paymentCurrency = listing.paymentCurrency;
        uint256 price = listing.price;
        address seller = listing.seller;

        // Effects
        listing.active = false;

        // Interactions: pull buyer payment (fee-on-transfer safe), distribute, deliver NFT.
        _pullPayment(paymentCurrency, price);
        _distributeProceeds(nftContract, tokenId, price, seller, paymentCurrency);
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);

        emit ItemBought(msg.sender, nftContract, tokenId, price, paymentCurrency);
    }

    /**
     * @notice Atomic basket checkout for fixed-price listings on THIS
     *         chain. See `IArtvybeMarketplace.batchBuy` for the
     *         partial-fill / strict-mode contract.
     *
     *         Multi-currency layout: every native item is paid out of the
     *         shared `msg.value` (we pre-tally `totalExpectedNative` and
     *         require an exact match so we never leave dust escrowed by
     *         accident). Every ERC20 item is pulled in-loop via
     *         `safeTransferFrom`, so a skipped ERC20 item never costs the
     *         buyer anything beyond gas.
     *
     *         CEI per item: validate -> flip `listing.active = false` ->
     *         pull payment -> distribute -> deliver NFT. Combined with
     *         `nonReentrant` on the whole batch this prevents any single
     *         hostile NFT receiver / royalty receiver from re-entering
     *         the marketplace mid-batch and seeing partial state.
     *
     *         Skipped items emit `BatchItemSkipped` with a short ASCII
     *         reason; the batch ends with `BatchBuyExecuted` summarising
     *         the totals so the frontend can refresh state in one read.
     */
    // Same per-item rationale as `buyFixed`: the balance-delta check on
    // ERC20 transferFrom is protected by `nonReentrant` on the whole
    // batch, and the listing flip happens before any external call.
    // slither-disable-next-line reentrancy-balance,reentrancy-no-eth,reentrancy-eth
    function batchBuy(BatchBuyItem[] calldata items, bool strict)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        uint256 n = items.length;
        if (n == 0) revert BatchEmpty();
        if (n > MAX_BATCH_BUY) revert BatchTooLarge();

        // ----- Pass 1: tally expected native so msg.value can be checked
        //       exactly. Buyers always send the full expected total; any
        //       portion belonging to a skipped item is refunded at the
        //       end of the tx (or credited to pendingRefunds on push
        //       failure). ERC20 items are not summed here because we
        //       pull them per-item in pass 2 — skipping an ERC20 item
        //       costs nothing.
        uint256 totalExpectedNative = 0;
        for (uint256 i = 0; i < n; i++) {
            if (items[i].expectedCurrency == NATIVE) {
                totalExpectedNative += items[i].expectedPrice;
            }
        }
        if (msg.value != totalExpectedNative) revert WrongNativeAmount();

        // ----- Pass 2: try each buy. -----
        uint256 boughtCount = 0;
        uint256 skippedCount = 0;
        uint256 spentNative = 0;

        for (uint256 i = 0; i < n; i++) {
            BatchBuyItem calldata b = items[i];
            Listing storage listing = listings[b.nftContract][b.tokenId];

            bytes32 skipReason;
            if (!listing.active) {
                skipReason = SKIP_LISTING_INACTIVE;
            } else if (listing.listingType != ListingType.FixedPrice) {
                skipReason = SKIP_NOT_FIXED_PRICE;
            } else if (listing.paymentCurrency != b.expectedCurrency) {
                skipReason = SKIP_CURRENCY_MISMATCH;
            } else if (listing.price != b.expectedPrice) {
                skipReason = SKIP_PRICE_MISMATCH;
            } else if (listing.seller == msg.sender) {
                skipReason = SKIP_SELF_PURCHASE;
            }

            if (skipReason != bytes32(0)) {
                if (strict) revert BatchStrictFailure();
                unchecked { skippedCount++; }
                emit BatchItemSkipped(msg.sender, b.nftContract, b.tokenId, skipReason);
                continue;
            }

            // Snapshot before flipping state so we don't read storage
            // again after `listing.active = false` (and so a malicious
            // distribute-side hook can't observe a half-mutated listing).
            address paymentCurrency = listing.paymentCurrency;
            uint256 price = listing.price;
            address seller = listing.seller;

            // Effects.
            listing.active = false;

            // Interactions: pull payment for this item.
            if (paymentCurrency == NATIVE) {
                // The native funds for this item were attached up front
                // via msg.value (validated above). Just credit the
                // escrow ledger; _distributeProceeds will draw it down.
                spentNative += price;
                totalOwed[NATIVE] += price;
            } else {
                IERC20 token = IERC20(paymentCurrency);
                uint256 before = token.balanceOf(address(this));
                token.safeTransferFrom(msg.sender, address(this), price);
                uint256 received = token.balanceOf(address(this)) - before;
                if (received != price) revert FeeOnTransferUnsupported();
                totalOwed[paymentCurrency] += price;
            }

            _distributeProceeds(b.nftContract, b.tokenId, price, seller, paymentCurrency);
            IERC721(b.nftContract).safeTransferFrom(address(this), msg.sender, b.tokenId);

            unchecked { boughtCount++; }
            emit ItemBought(msg.sender, b.nftContract, b.tokenId, price, paymentCurrency);
        }

        // ----- Native refund for the unbought (skipped) portion. -----
        // Pull-safe: a buyer that's a contract with a hostile receive()
        // gets credited via pendingRefunds instead of bricking the batch.
        uint256 nativeRefund = totalExpectedNative - spentNative;
        if (nativeRefund > 0) {
            (bool ok, ) = msg.sender.call{value: nativeRefund, gas: REFUND_PUSH_GAS}("");
            if (!ok) {
                pendingRefunds[NATIVE][msg.sender] += nativeRefund;
                totalOwed[NATIVE] += nativeRefund;
                emit RefundCredited(msg.sender, NATIVE, nativeRefund);
            }
        }

        emit BatchBuyExecuted(msg.sender, n, boughtCount, skippedCount, nativeRefund);
    }

    // -----------------------------------------------------------------
    // Bidding
    // -----------------------------------------------------------------

    // Protected by nonReentrant. Slither flags the balance-delta check
    // against ERC20 transferFrom (reentrancy-balance), the bidder
    // bookkeeping after the transfer (reentrancy-no-eth), and the
    // pendingRefunds bump after a failed excess-push (reentrancy-eth).
    // None are exploitable: the lock prevents re-entry into any
    // state-mutating marketplace function.
    // slither-disable-next-line reentrancy-balance,reentrancy-no-eth,reentrancy-eth
    function placeBid(address nftContract, uint256 tokenId, uint256 bidAmount)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Listing storage listing = listings[nftContract][tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.listingType != ListingType.EnglishAuction) revert ListingNotFound();
        if (block.timestamp >= listing.endTime) revert AuctionNotEnded();
        if (msg.sender == listing.seller) revert SelfPurchase();

        address paymentCurrency = listing.paymentCurrency;
        uint256 highestBid = _getHighestBid(listing);
        // Per-currency increment so chains with 6-decimal stablecoins (e.g.
        // USDC on Ethereum) don't get gated by an 18-decimal default.
        uint256 minBid = highestBid == 0
            ? listing.price
            : highestBid + minBidIncrementFor(paymentCurrency);

        uint256 actualBid;
        if (paymentCurrency == NATIVE) {
            if (msg.value < minBid) revert InsufficientBid();
            actualBid = msg.value;
        } else {
            if (msg.value > 0) revert InvalidPrice();
            if (bidAmount < minBid) revert InsufficientBid();
            actualBid = bidAmount;
        }

        // Look up the bidder's previous escrowed bid (if any) so we only
        // pull the *difference* this tx.
        int256 existingIndex = _findBidderIndex(listing, msg.sender);
        uint256 previousBid = existingIndex >= 0
            ? listing.topBidders[uint256(existingIndex)].bidAmount
            : 0;

        if (actualBid <= previousBid) revert InsufficientBid();
        uint256 netPayment = actualBid - previousBid;
        uint256 excessNative = 0;

        // ------ Pull payment (only interaction in the "pull" half) ------
        if (paymentCurrency == NATIVE) {
            if (msg.value < netPayment) revert InsufficientBid();
            excessNative = msg.value - netPayment;
            totalOwed[NATIVE] += netPayment;
        } else {
            IERC20 token = IERC20(paymentCurrency);
            uint256 before = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), netPayment);
            uint256 received = token.balanceOf(address(this)) - before;
            if (received != netPayment) revert FeeOnTransferUnsupported();
            totalOwed[paymentCurrency] += netPayment;
        }

        // ------ Effects (top-5 bookkeeping) ------
        (bool added, address refundBidder, uint256 refundAmount) = _addOrUpdateBidder(listing, msg.sender, actualBid);
        if (!added) revert InsufficientBid();

        // ------ Interactions: refunds happen LAST so all state is settled
        //         before any external push call. With nonReentrant this is
        //         already safe; CEI ordering makes that property explicit.
        if (refundBidder != address(0) && refundAmount > 0) {
            _safeRefund(refundBidder, paymentCurrency, refundAmount);
        }
        if (excessNative > 0) {
            // Try to push excess straight back to the bidder; on failure
            // credit pendingRefunds so a contract-bidder doesn't lose it.
            (bool ok, ) = msg.sender.call{value: excessNative, gas: REFUND_PUSH_GAS}("");
            if (!ok) {
                pendingRefunds[NATIVE][msg.sender] += excessNative;
                totalOwed[NATIVE] += excessNative;
                emit RefundCredited(msg.sender, NATIVE, excessNative);
            }
        }

        emit BidPlaced(msg.sender, nftContract, tokenId, actualBid, paymentCurrency);
    }

    function finalizeAuction(address nftContract, uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[nftContract][tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.listingType != ListingType.EnglishAuction) revert ListingNotFound();
        if (block.timestamp < listing.endTime) revert AuctionNotEnded();

        address paymentCurrency = listing.paymentCurrency;
        address seller = listing.seller;
        uint256 bidderCount = listing.bidderCount;
        Bidder[5] memory snapshot = listing.topBidders;

        // ------ Effects (all state changes BEFORE any external call) ------
        listing.active = false;
        for (uint256 i = 0; i < bidderCount; i++) {
            listing.topBidders[i] = Bidder(address(0), 0);
        }
        listing.bidderCount = 0;

        // ------ Interactions ------
        if (bidderCount == 0) {
            IERC721(nftContract).safeTransferFrom(address(this), seller, tokenId);
            emit AuctionFinalized(address(0), nftContract, tokenId, 0, paymentCurrency);
            return;
        }

        address winner = snapshot[0].bidder;
        uint256 winningBid = snapshot[0].bidAmount;

        // Refund losing bidders via pull-safe path so a single bad bidder
        // can never block finalization.
        for (uint256 i = 1; i < bidderCount; i++) {
            Bidder memory b = snapshot[i];
            if (b.bidder != address(0) && b.bidAmount > 0) {
                _safeRefund(b.bidder, paymentCurrency, b.bidAmount);
            }
        }

        // The winning bid's escrow funds the distribution. totalOwed
        // already includes it (from placeBid), so _distributeProceeds
        // simply decrements as funds go out.
        _distributeProceeds(nftContract, tokenId, winningBid, seller, paymentCurrency);
        IERC721(nftContract).safeTransferFrom(address(this), winner, tokenId);

        emit AuctionFinalized(winner, nftContract, tokenId, winningBid, paymentCurrency);
    }

    /// @notice Bidder can withdraw their bid prior to auction end. Allowed
    ///         even when paused so funds are always reachable in an
    ///         incident.
    function cancelBid(address nftContract, uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[nftContract][tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.listingType != ListingType.EnglishAuction) revert ListingNotFound();
        if (block.timestamp >= listing.endTime) revert AuctionNotEnded();

        int256 bidderIndex = _findBidderIndex(listing, msg.sender);
        if (bidderIndex < 0) revert NotBidder();

        uint256 bidAmount = listing.topBidders[uint256(bidderIndex)].bidAmount;
        _removeBidder(listing, msg.sender);
        _safeRefund(msg.sender, listing.paymentCurrency, bidAmount);

        emit BidCancelled(msg.sender, nftContract, tokenId, bidAmount, listing.paymentCurrency);
    }

    /// @notice Seller cancels their listing. Allowed even when paused so
    ///         the NFT and bidder funds are always reachable.
    function cancelListing(address nftContract, uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[nftContract][tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.seller != msg.sender) revert NotListingOwner();
        if (listing.listingType == ListingType.EnglishAuction && block.timestamp >= listing.endTime) {
            revert InvalidParameters();
        }

        listing.active = false;

        // Return NFT first; then refund any bidders via the pull-safe path.
        IERC721(nftContract).safeTransferFrom(address(this), listing.seller, tokenId);

        if (listing.listingType == ListingType.EnglishAuction && listing.bidderCount > 0) {
            _refundAllBidders(listing);
        }

        emit ListingCancelled(msg.sender, nftContract, tokenId);
    }

    // -----------------------------------------------------------------
    // Offers
    // -----------------------------------------------------------------

    function makeOffer(
        address nftContract,
        uint256 tokenId,
        address paymentCurrency,
        uint256 offerAmount,
        uint256 offerDuration
    ) external payable whenNotPaused nonReentrant {
        if (offerAmount == 0) revert InvalidPrice();
        if (offerDuration < MIN_OFFER_DURATION || offerDuration > MAX_OFFER_DURATION) revert InvalidDuration();
        _assertCurrencyAllowed(paymentCurrency);

        Listing storage listing = listings[nftContract][tokenId];
        if (listing.active) revert InvalidParameters();

        if (offers[nftContract][tokenId][msg.sender].active) revert OfferAlreadyExists();

        address nftOwner = IERC721(nftContract).ownerOf(tokenId);
        if (nftOwner == address(0) || nftOwner == msg.sender) revert InvalidParameters();

        _pullPayment(paymentCurrency, offerAmount);

        offers[nftContract][tokenId][msg.sender] = Offer({
            offerer: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            offerAmount: offerAmount,
            paymentCurrency: paymentCurrency,
            offerTime: block.timestamp,
            expiryTime: block.timestamp + offerDuration,
            active: true
        });

        offerers[nftContract][tokenId].push(msg.sender);

        emit OfferMade(msg.sender, nftContract, tokenId, offerAmount, paymentCurrency, block.timestamp + offerDuration);
    }

    function acceptOffer(
        address nftContract,
        uint256 tokenId,
        address offerer
    ) external whenNotPaused nonReentrant {
        Offer storage offer = offers[nftContract][tokenId][offerer];
        if (!offer.active) revert OfferNotActive();
        if (offer.expiryTime < block.timestamp) revert OfferExpired();

        address nftOwner = IERC721(nftContract).ownerOf(tokenId);
        if (msg.sender != nftOwner) revert NotNFTOwner();

        address paymentCurrency = offer.paymentCurrency;
        uint256 offerAmount = offer.offerAmount;

        // Effects
        offer.active = false;
        _removeOfferer(nftContract, tokenId, offerer);

        // Refund every OTHER active offerer via pull-safe path.
        _cancelAllOtherOffers(nftContract, tokenId, offerer);

        // Single transfer: NFT goes seller -> offerer directly (no escrow hop).
        IERC721(nftContract).safeTransferFrom(msg.sender, offerer, tokenId);

        // The accepted offer's escrow funds the distribution. totalOwed
        // already includes offerAmount (from makeOffer); _distributeProceeds
        // decrements as funds go out.
        _distributeProceeds(nftContract, tokenId, offerAmount, msg.sender, paymentCurrency);

        emit OfferAccepted(offerer, msg.sender, nftContract, tokenId, offerAmount, paymentCurrency);
    }

    function rejectOffer(
        address nftContract,
        uint256 tokenId,
        address offerer
    ) external whenNotPaused nonReentrant {
        Offer storage offer = offers[nftContract][tokenId][offerer];
        if (!offer.active) revert OfferNotActive();

        address nftOwner = IERC721(nftContract).ownerOf(tokenId);
        if (msg.sender != nftOwner) revert NotNFTOwner();

        uint256 amount = offer.offerAmount;
        address currency = offer.paymentCurrency;
        offer.active = false;
        _removeOfferer(nftContract, tokenId, offerer);
        _safeRefund(offerer, currency, amount);

        emit OfferRejected(offerer, nftContract, tokenId);
    }

    /// @notice Allowed even when paused so offerers can always pull their
    ///         escrow back.
    function cancelOffer(address nftContract, uint256 tokenId) external nonReentrant {
        Offer storage offer = offers[nftContract][tokenId][msg.sender];
        if (!offer.active) revert OfferNotActive();
        if (msg.sender != offer.offerer) revert NotOfferOwner();

        uint256 amount = offer.offerAmount;
        address currency = offer.paymentCurrency;
        offer.active = false;
        _removeOfferer(nftContract, tokenId, msg.sender);
        _safeRefund(msg.sender, currency, amount);

        emit OfferCancelled(msg.sender, nftContract, tokenId);
    }

    // -----------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------

    function getListing(address nftContract, uint256 tokenId) external view returns (Listing memory) {
        return listings[nftContract][tokenId];
    }

    function isListingActive(address nftContract, uint256 tokenId) external view returns (bool) {
        return listings[nftContract][tokenId].active;
    }

    function getOffer(address nftContract, uint256 tokenId, address offerer) external view returns (Offer memory) {
        return offers[nftContract][tokenId][offerer];
    }

    function getActiveOffers(address nftContract, uint256 tokenId) external view returns (Offer[] memory) {
        address[] memory list = offerers[nftContract][tokenId];
        uint256 active = 0;
        for (uint256 i = 0; i < list.length; i++) {
            Offer storage o = offers[nftContract][tokenId][list[i]];
            if (o.active && o.expiryTime >= block.timestamp) active++;
        }
        Offer[] memory out = new Offer[](active);
        uint256 j = 0;
        for (uint256 i = 0; i < list.length; i++) {
            Offer storage o = offers[nftContract][tokenId][list[i]];
            if (o.active && o.expiryTime >= block.timestamp) {
                out[j++] = o;
            }
        }
        return out;
    }

    function getTopBidders(address nftContract, uint256 tokenId) external view returns (Bidder[5] memory) {
        return listings[nftContract][tokenId].topBidders;
    }

    function getBidderCount(address nftContract, uint256 tokenId) external view returns (uint256) {
        return listings[nftContract][tokenId].bidderCount;
    }

    function getHighestBid(address nftContract, uint256 tokenId) external view returns (uint256) {
        return _getHighestBid(listings[nftContract][tokenId]);
    }

    function getHighestBidder(address nftContract, uint256 tokenId) external view returns (address) {
        return _getHighestBidder(listings[nftContract][tokenId]);
    }

    // -----------------------------------------------------------------
    // Internal: offerer array maintenance + cleanup
    // -----------------------------------------------------------------

    function _removeOfferer(address nftContract, uint256 tokenId, address offerer) internal {
        address[] storage list = offerers[nftContract][tokenId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == offerer) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }

    /// @dev Refund every other active offerer (used in acceptOffer).
    ///      CEI two-pass: mark inactive + collect refund jobs first, then
    ///      issue all refunds. Pull-safe so one hostile offerer can never
    ///      block accept.
    function _cancelAllOtherOffers(
        address nftContract,
        uint256 tokenId,
        address acceptedOfferer
    ) internal {
        address[] memory snapshot = offerers[nftContract][tokenId];

        address[] memory users = new address[](snapshot.length);
        address[] memory currencies = new address[](snapshot.length);
        uint256[] memory amounts = new uint256[](snapshot.length);
        uint256 n = 0;

        // ------ Effects ------
        for (uint256 i = snapshot.length; i > 0; i--) {
            address who = snapshot[i - 1];
            if (who == acceptedOfferer) continue;
            Offer storage o = offers[nftContract][tokenId][who];
            if (!o.active) continue;

            users[n] = who;
            currencies[n] = o.paymentCurrency;
            amounts[n] = o.offerAmount;
            n++;

            o.active = false;
            _removeOfferer(nftContract, tokenId, who);
        }

        // ------ Interactions ------
        for (uint256 i = 0; i < n; i++) {
            _safeRefund(users[i], currencies[i], amounts[i]);
            emit OfferCancelled(users[i], nftContract, tokenId);
        }
    }

    // -----------------------------------------------------------------
    // Royalty resolution
    // -----------------------------------------------------------------

    function _resolveCreatorRoyalty(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    ) internal view returns (address receiver, uint256 royaltyAmount) {
        CollectionRoyaltyConfig memory cfg = collectionRoyalties[nftContract];
        if (cfg.enabled && cfg.bps > 0 && cfg.receiver != address(0)) {
            return (cfg.receiver, (salePrice * cfg.bps) / 10000);
        }

        try ERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address ercReceiver, uint256 ercAmount) {
            if (ercReceiver != address(0) && ercAmount > 0) {
                return (ercReceiver, ercAmount);
            }
        } catch {}

        return (address(0), 0);
    }

    function _tryOwnableOwner(address target) internal view returns (address) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature("owner()"));
        if (!ok || data.length < 32) return address(0);
        return abi.decode(data, (address));
    }

    function _canManageCollectionRoyalty(address collection, address account) internal view returns (bool) {
        if (account == admin || account == owner()) return true;
        if (collectionRoyaltyAdmin[collection] == account) return true;
        address contractOwner = _tryOwnableOwner(collection);
        return contractOwner != address(0) && contractOwner == account;
    }

    // -----------------------------------------------------------------
    // Distribution
    // -----------------------------------------------------------------

    /// @dev Distribute `salePrice` from a settlement. Used by both buyFixed
    ///      (where _pullPayment added `salePrice` to `totalOwed` in the
    ///      same tx) and by finalizeAuction / acceptOffer (where the bid /
    ///      offer escrow already accounts for `salePrice` in `totalOwed`).
    ///
    ///      In both cases the invariant is the same:
    ///        - `_payRequired(treasury, …)` debits platformFee from totalOwed
    ///          on success, reverts on failure (acceptable: treasury is
    ///          owner-controlled).
    ///        - `_safeRefund(royalty, …)` and `_safeRefund(seller, …)` debit
    ///          totalOwed only when the push succeeds. On push failure they
    ///          credit pendingRefunds and leave totalOwed unchanged, so
    ///          "money owed to user X" stays tracked until X pulls it.
    function _distributeProceeds(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice,
        address seller,
        address paymentCurrency
    ) internal {
        uint256 platformFee = (salePrice * platformFeeBps) / 10000;
        uint256 remaining = salePrice - platformFee;

        (address royaltyReceiver, uint256 royaltyAmount) = _resolveCreatorRoyalty(nftContract, tokenId, salePrice);
        // Cap royalty at remaining to avoid silently dropping it on
        // misconfigured ERC-2981 implementations.
        if (royaltyAmount > remaining) {
            royaltyAmount = remaining;
        }

        _payRequired(platformTreasury, paymentCurrency, platformFee);

        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            _safeRefund(royaltyReceiver, paymentCurrency, royaltyAmount);
            remaining -= royaltyAmount;
        }

        if (remaining > 0) {
            _safeRefund(seller, paymentCurrency, remaining);
        }
    }

    // -----------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------

    function setCollectionRoyaltyAdmin(address collection, address adminWallet) external {
        if (msg.sender != admin && msg.sender != owner()) {
            address contractOwner = _tryOwnableOwner(collection);
            if (contractOwner != msg.sender) revert NotRoyaltyAdmin();
        }
        if (adminWallet == address(0)) revert InvalidParameters();
        collectionRoyaltyAdmin[collection] = adminWallet;
        emit CollectionRoyaltyAdminUpdated(collection, adminWallet);
    }

    /// @notice Revoke a previously assigned royalty admin for `collection`.
    ///         Same auth model as `setCollectionRoyaltyAdmin`.
    function clearCollectionRoyaltyAdmin(address collection) external {
        if (msg.sender != admin && msg.sender != owner()) {
            address contractOwner = _tryOwnableOwner(collection);
            if (contractOwner != msg.sender) revert NotRoyaltyAdmin();
        }
        delete collectionRoyaltyAdmin[collection];
        emit CollectionRoyaltyAdminCleared(collection);
    }

    function configureCollectionRoyalty(
        address collection,
        address receiver,
        uint96 bps
    ) external {
        if (!_canManageCollectionRoyalty(collection, msg.sender)) revert NotRoyaltyAdmin();
        if (bps > MAX_FEE_BPS) revert InvalidParameters();
        if (receiver == address(0)) revert InvalidParameters();

        collectionRoyalties[collection] = CollectionRoyaltyConfig({
            receiver: receiver,
            bps: bps,
            enabled: true
        });
        emit CollectionRoyaltyUpdated(collection, receiver, bps);
    }

    function clearCollectionRoyalty(address collection) external {
        if (!_canManageCollectionRoyalty(collection, msg.sender)) revert NotRoyaltyAdmin();
        delete collectionRoyalties[collection];
        emit CollectionRoyaltyCleared(collection);
    }

    function getCollectionRoyalty(
        address collection
    ) external view returns (address receiver, uint96 bps, bool enabled) {
        CollectionRoyaltyConfig memory cfg = collectionRoyalties[collection];
        return (cfg.receiver, cfg.bps, cfg.enabled);
    }

    function setAdmin(address newAdmin) external onlyOwner {
        if (newAdmin == address(0)) revert InvalidParameters();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    function getAdmin() external view returns (address) {
        return admin;
    }

    function setPlatformTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidParameters();
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        emit PlatformTreasuryUpdated(oldTreasury, newTreasury);
    }

    function setPlatformFeeBps(uint96 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidParameters();
        uint96 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps);
    }

    function setPaused(bool paused) external onlyOwner {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Admin garbage collection: refund and clear EXPIRED offers
    ///         only. Cannot forcibly cancel valid in-window offers.
    ///         CEI two-pass: effects first, interactions second.
    function cancelAllOffers(address nftContract, uint256 tokenId) external onlyAdmin nonReentrant {
        address[] memory snapshot = offerers[nftContract][tokenId];

        address[] memory users = new address[](snapshot.length);
        address[] memory currencies = new address[](snapshot.length);
        uint256[] memory amounts = new uint256[](snapshot.length);
        uint256 n = 0;

        // ------ Effects ------
        for (uint256 i = snapshot.length; i > 0; i--) {
            address who = snapshot[i - 1];
            Offer storage offer = offers[nftContract][tokenId][who];
            if (!offer.active) continue;
            if (offer.expiryTime >= block.timestamp) revert OfferNotExpired();

            users[n] = who;
            currencies[n] = offer.paymentCurrency;
            amounts[n] = offer.offerAmount;
            n++;

            offer.active = false;
            _removeOfferer(nftContract, tokenId, who);
        }

        // ------ Interactions ------
        for (uint256 i = 0; i < n; i++) {
            _safeRefund(users[i], currencies[i], amounts[i]);
            emit OfferCancelled(users[i], nftContract, tokenId);
        }

        emit AllOffersCancelled(nftContract, tokenId, n);
    }

    // -----------------------------------------------------------------
    // Emergency recovery — restricted to non-escrow funds, paused only
    // -----------------------------------------------------------------

    /// @notice Recover native funds that aren't owed to users (e.g. ETH
    ///         sent in by mistake via the receive() hook). Recovery is
    ///         only callable while the marketplace is paused — gives users
    ///         an explicit window to exit before recovery activity, and
    ///         ensures `address(this).balance` is the only thing in flux.
    function recoverETH(address to, uint256 amount) external onlyOwner whenPaused {
        if (to == address(0)) revert InvalidParameters();
        uint256 owed = totalOwed[NATIVE];
        uint256 bal = address(this).balance;
        if (bal <= owed) revert NothingToRecover();
        uint256 recoverable = bal - owed;
        if (amount == 0 || amount > recoverable) amount = recoverable;
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Recover ERC20 funds that aren't owed to users. Subject to
    ///         the same paused-only and non-escrow constraints as
    ///         `recoverETH`.
    function recoverERC20(address token, address to, uint256 amount) external onlyOwner whenPaused {
        if (to == address(0) || token == address(0)) revert InvalidParameters();
        uint256 owed = totalOwed[token];
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal <= owed) revert NothingToRecover();
        uint256 recoverable = bal - owed;
        if (amount == 0 || amount > recoverable) amount = recoverable;
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Recover NFTs that are NOT in an active listing. Recovery
    ///         can never cancel a live listing out from under a seller.
    function recoverNFT(address nftContract, uint256 tokenId, address to) external onlyOwner whenPaused {
        if (to == address(0)) revert InvalidParameters();
        if (listings[nftContract][tokenId].active) revert InvalidParameters();
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }

    receive() external payable {}

    /// @dev Reserved storage gap for future upgrades. Originally 45;
    ///      shrunk by 2 for `totalOwed` + `pendingRefunds`, then by 1 more
    ///      for `paymentCurrencies`.
    uint256[42] private __gap;
}
