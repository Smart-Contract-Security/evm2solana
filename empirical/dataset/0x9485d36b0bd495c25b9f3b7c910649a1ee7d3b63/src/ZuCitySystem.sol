// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {Ownable} from "solady/auth/Ownable.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {IReceiptValidator} from "./interfaces/IReceiptValidator.sol";
import {INFTRenderer} from "./interfaces/INFTRenderer.sol";
import {IZuCitySystem} from "./interfaces/IZuCitySystem.sol";
import {
    ReceiptStatus,
    ManagerConfig,
    Item,
    Receipt,
    ItemDisplayData,
    ReceiptDisplayData,
    DiscountParams,
    ReceiptDates,
    InvalidItemManager,
    InvalidBanDeadline,
    InvalidReceiptLength,
    ReceiptAlreadyFinalized,
    ManagerBanned,
    InvalidBulkPayment,
    ReceiptNotTransferable,
    ItemNotTransferable,
    ItemNeedsPrice,
    ReferrerFeeTooHigh,
    CancelFeeTooHigh,
    RecipientBan,
    MixedManagers,
    MixedPaymentTokens,
    InvalidToken,
    InsufficientPayment
} from "./common/ZuCityTypes.sol";
import {ZuCityCalendar} from "./common/ZuCityCalendar.sol";
import {ZuCitySystemLibrary} from "./common/ZuCitySystemLibrary.sol";

/**
 * @notice Flexible contract for events, coliving, and other community related products/services
 * @dev Year parameter is 0-indexed to Zuzalu year 0 (0AZ) aka Japan Emperor years
 *         (令和 5年) aka Etherem year 7 (7AE) aka 2023 AD.
 *         So 0 = 2023, 2023 = 4046
 */
contract ZuCitySystem is IZuCitySystem, Ownable, ERC721, EIP712, Multicallable, ReentrancyGuard {
    uint256 public receiptsCounter; // inc per created
    // end slot 1
    uint64 internal itemsCounter; // inc per created

    uint16 public cancelFeeBps = 30_00; //slashing upon cancelation
    uint16 public referrerFeeBps = 10_00; // split from partner sites

    ///// @DEV Section: core protocol logic
    /**
     * @notice intergalactic bitmap calendar that doesnt use relative time.
     *             ZuCity System config for Earth days.
     *             Each bit is one day with 364 days available per Earth year
     * @dev Key: keccak256(abi.encodePacked(listingId, year, segmentId))
     *         segmentId = 0 or 1 for first half or second half of year.
     *         Value: 256 bits [182 bits for days | 74 bits empty]
     */
    mapping(bytes32 => uint256) public availabilityCalendar;
    /// @notice Token reserves: receiver => token => amount
    /// @dev Allows separate tracking of b.manager reserves vs referrer rewards
    mapping(address => mapping(address => uint256)) public tokenReserves;

    ///// @DEV Section: raw data storage
    mapping(uint256 => Receipt) public receipts;
    mapping(uint64 => Item) public items;

    ///// @DEV Section: extra social security
    /**
     * @notice users that are banned network wide and a timestamp when the ban ends.
     * @dev not in receiptValidator so that is network wide and integrated into every touchpoint cheaply
     * @dev uint256 for cheaper gas since we only read for comparators
     */
    mapping(address => uint256) public bans;
    /// @notice allow secure handoff of item ownership between managers with propose/accept flow
    mapping(uint64 => address) public pendingItemManager;
    /// @notice Manager-level config: receiptValidator shared across all items for a manager.
    ///         Payment token is per-item (see Item.token), so a single manager can price
    ///         different items in different ERC20s without re-configuring this mapping.
    mapping(address => ManagerConfig) public managerConfigs;
    /// @notice Manager-level config: allows displaying custom NFTs per item or receipt isntead of Default Renderer
    mapping(address => INFTRenderer) public managerRenderer;
    /// @notice Manager-level config: who can manage bookings for them. auto switches when item changes owner
    /// item manager -> immigration officer -> can manage bookings for them
    mapping(address => mapping(address => bool)) public immigration;

    constructor(address manager) {
        _initializeOwner(manager);
    }

    // core functions
    /// @notice Register a new item. Token is per-item now — caller chooses the ERC20
    ///         buyers must pay in, independent of any manager-level config.
    function list(Item calldata l) external onlyOwner returns (uint64) {
        if (l.minUnitPrice == 0) revert ItemNeedsPrice();
        if (l.manager == address(0)) revert InvalidItemManager();
        // payment token must be set on the item itself
        if (l.token == address(0)) revert InvalidToken();
        uint64 id = itemsCounter;
        items[id] = l;
        ++itemsCounter;

        emit ZuCitySystemLibrary.ListItem(
            id, l.manager, uint8(l.itemType), l.transferable, l.unlimited, l.token, l.minUnitPrice
        );
        return id;
    }

    /**
     * @notice Buys a single item listed in ZuCity System, issues NFT to requested recipient,
     *             and attempts to autoconfirm purchase using manager's receiptValidator contract
     *             Blocks dates in bitmap calendar if a scarce item.
     *             totalPaid MUST be 0 OR at least the items defined min price for the timelength requested
     *             totalPaid MAY be higher than minimum to overbid and ensure confirmation during peak ticket/rental times.
     * @dev Set receipt price to 0 to auto accept lowest price available
     * @param b Receipt data for the requested purchase
     * @param referrer Optional referrer address to receive fee split (0 if none)
     * @return finalDicsountPrice Final paid price after discounts applied
     * @return receiptId NFT ID for the pending/accepted purchase
     */
    function buy(Receipt calldata b, address referrer) external nonReentrant returns (uint256, uint256) {
        Item memory item = items[b.listingId];
        if (_isBanned(item.manager)) revert ManagerBanned();
        ManagerConfig memory config = managerConfigs[item.manager];

        uint256 id = _makeReceipt(b);

        uint256 minTotalPrice = ZuCitySystemLibrary.getDiscountedPrice(
            DiscountParams({
                totalPrice: item.minUnitPrice * b.daysCount,
                itemCount: uint8(1),
                totalQuantity: uint16(b.daysCount),
                buyer: msg.sender
            }),
            config.receiptValidator
        );
        // let people overbid but not underbid pricing
        uint256 total = b.totalPaid < minTotalPrice ? minTotalPrice : b.totalPaid;
        if (total > type(uint128).max) revert InvalidToken();
        receipts[id].totalPaid = uint128(total);

        if (referrer == address(0)) {
            unchecked {
                tokenReserves[item.manager][item.token] += total;
            }
        } else {
            uint128 referrerPayout = uint128((total * referrerFeeBps) / ZuCitySystemLibrary.BPS_DENOM);
            receipts[id].referrerFee = referrerPayout;
            unchecked {
                // Track Manager and referrer reserves separately
                tokenReserves[item.manager][item.token] += total - referrerPayout;
                tokenReserves[referrer][item.token] += referrerPayout;
            }
        }

        emit ZuCitySystemLibrary.MakePayment(id, b.listingId, referrer, minTotalPrice, total, id);

        // attempt autoconfirm using item's manager and manager's receiptValidator
        _confirm(id, b.recipient, item.manager, config.receiptValidator);
        SafeTransferLib.safeTransferFrom(item.token, msg.sender, address(this), total);

        return (total, id);
    }

    /**
     * @notice Buy multiple items in bulk to get a bulk discount
     *             First receipt is the "leader" - person responsible for entire party purchasing items together
     *             First receipt handles all payments data, is first confirmed/denied, and takes responsibility
     *             for all recipients on sub-receipts during their time at ZuCity together.
     *             Therefore all payment and on/offchain data is routed through first receipt.
     * @dev All items must belong to the same manager for token/receiptValidator.
     * @dev Set first receipt price to 0 to auto accept lowest price available
     * @param reservations Array of receipts - all MUST have the same manager.
     * @param referrer Optional address to receive referrer fees (0 if none)
     * @return finalDicsountPrice Actual amount of tokens paid by user after all discounts applied
     * @return receiptIds Array of receipt IDs. Same ordering as reservations[] receipts.
     */
    function bulkBuy(Receipt[] calldata reservations, address referrer)
        external
        nonReentrant
        returns (uint256, uint256[] memory)
    {
        if (reservations.length == 0) revert InvalidReceiptLength();

        // Load first item + config once — extract fields to avoid struct on stack
        Item storage parentItem = items[reservations[0].listingId];
        address manager = parentItem.manager;
        address paymentToken = parentItem.token;
        if (_isBanned(manager)) revert ManagerBanned();

        // fullPrice = sum of all receipts for their entire individual lengths
        uint256 fullPrice;
        // totalQuantity = mainly cosmetic for receiptValidator discount calculations
        uint16 totalQuantity;
        // Count UNIQUE listingIds so discount tiers can't be arbed via duplicated reservation receipt items.
        uint8 uniqueItemCount;

        // Batch-allocate receipt IDs with a single SSTORE vs ++receiptsCounter per loop
        uint256 startId = receiptsCounter;
        receiptsCounter = startId + reservations.length;
        uint256[] memory receiptIds = new uint256[](reservations.length);

        // Validate reservations, collect unit prices, check availability, and create receipts
        for (uint256 i = 0; i < reservations.length; i++) {
            // allow people to overbid using the first receipt totalPaid price
            // we only save final discounted price to first receipt
            // bc expensive to recompute per receipt totalPaid and update after receiving bulk discount
            // so match bulk receipts offchain and prevent sub-receipts from draining manager reserves using cancel() by setting totalPaid = 0
            // even if they want to overbid on one item, we treat entire set as single reservation so SHOULD approv/cancel one receipt with all others
            if (i != 0 && reservations[i].totalPaid != 0) revert InvalidBulkPayment();

            uint64 listingId = reservations[i].listingId;
            // Access item fields directly from storage to avoid stack-too-deep. only 3 reads
            Item storage item = items[listingId];

            // MUST share manager (one receiptValidator applies) and token (one reserve bucket)
            if (item.manager != manager) revert MixedManagers();
            if (item.token != paymentToken) revert MixedPaymentTokens();

            // keep checkto prevent overflow and buying tickets for 0
            uint256 receiptPrice = item.minUnitPrice * reservations[i].daysCount;
            fullPrice += receiptPrice;
            unchecked {
                // accrue full daily price to pass to receiptValidator for discounts.
                // max uint16 / max uint8 = max 256 items at max daysCount
                totalQuantity += reservations[i].daysCount;

                // Create receipt with pre-allocated ID. If scarce check calendar availability and reserve
                receiptIds[i] = _makeReceiptAt(reservations[i], startId + i);

                // Mark unique listingIds by scanning prior iterations (O(n*m) where m = duplicates seen;
                // bounded by reservations.length — cheaper than allocating a memory set for small N).
                bool seen;
                for (uint256 k = 0; k < i; k++) {
                    if (reservations[k].listingId == listingId) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) ++uniqueItemCount;
            }

            // emit per-receipt event for tracking, final bulk event with discount at end of func.
            // use 0 as discounted price to show them as non-final / invalid events.
            emit ZuCitySystemLibrary.MakePayment(receiptIds[i], listingId, referrer, receiptPrice, 0, receiptIds[0]);
        }

        // Get bulk discount price from receiptValidator
        IReceiptValidator nl = managerConfigs[manager].receiptValidator;
        uint256 discountedPrice = ZuCitySystemLibrary.getDiscountedPrice(
            DiscountParams({
                totalPrice: fullPrice, itemCount: uniqueItemCount, totalQuantity: totalQuantity, buyer: msg.sender
            }),
            nl
        );

        // allow overbidding if they so wish.
        fullPrice = reservations[0].totalPaid < discountedPrice ? discountedPrice : reservations[0].totalPaid;
        if (fullPrice > type(uint128).max) revert InvalidToken();
        receipts[receiptIds[0]].totalPaid = uint128(fullPrice);

        if (referrer == address(0)) {
            unchecked {
                tokenReserves[manager][paymentToken] += fullPrice;
            }
        } else {
            uint128 referrerPayout = uint128((fullPrice * referrerFeeBps) / ZuCitySystemLibrary.BPS_DENOM);
            receipts[receiptIds[0]].referrerFee = referrerPayout;
            unchecked {
                tokenReserves[manager][paymentToken] += fullPrice - referrerPayout;
                tokenReserves[referrer][paymentToken] += referrerPayout;
            }
        }

        // Emit bulk order summary
        emit ZuCitySystemLibrary.MakePayment(
            receiptIds[0], reservations[0].listingId, referrer, fullPrice, discountedPrice, receiptIds[0]
        );

        // attempt autoconfirm on first receipt. Manager can accept/cancel subreceipts ones if needed.
        _confirm(receiptIds[0], reservations[0].recipient, manager, nl);
        // accept token payment before confirming
        // tbh token vs confirm external call order irrelevant since manager sets both token and receiptValidator contract
        SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, address(this), fullPrice);

        return (discountedPrice, receiptIds);
    }

    /// @notice Creates receipt with auto-allocated ID. Used by buy() and gift().
    function _makeReceipt(Receipt calldata b) internal returns (uint256) {
        uint256 id = receiptsCounter;
        unchecked {
            ++receiptsCounter;
        }
        return _makeReceiptAt(b, id);
    }

    /**
     * @notice Creates receipt at a specific pre-allocated ID. Used by bulkBuy() to
     *             batch-allocate IDs with a single SSTORE instead of N increments.
     */
    function _makeReceiptAt(Receipt calldata b, uint256 id) internal returns (uint256) {
        ZuCitySystemLibrary.validateReceipt(b);

        receipts[id] = b; // Store receipt before setting token cache for redemption

        Item storage item = items[b.listingId];
        // snapshot payment token at creation time
        receipts[id].token = item.token;

        if (!item.unlimited) {
            ZuCityCalendar.reserveReceipt(availabilityCalendar, b);
        }

        emit ZuCitySystemLibrary.MakeReservation(id, b.listingId, b.recipient, b.year, b.startDay, b.daysCount);
        return id;
    }

    /**
     * Immigration, Manager, Or User Functions
     */

    /**
     * @notice Allows any receiptValidatored person, receipt item's manager, or system wide Immigration Officer to confirm a receipt
     *             Recipients are checked against item manager receiptValidator. Manager and Officer always confirm.
     *             Checks receipt and caller independently against manager receiptValidator requirements.
     *             Receipt MUST be Pending.
     * @param receiptId NFT to transfer
     */
    function confirm(uint256 receiptId) public returns (bool) {
        if (receipts[receiptId].status != ReceiptStatus.Pending) return false;

        Receipt storage r = receipts[receiptId];
        address manager = items[r.listingId].manager;
        return _confirm(receiptId, r.recipient, manager, managerConfigs[manager].receiptValidator);
    }

    /**
     * @notice checks if caller is a manager/officer or there is a receiptValidator for non-manager callers
     * @dev internal call so no checks on receipt status or other tangential logic.
     *
     * @dev CEI invariant: receipts[receiptId].status MUST be written BEFORE _safeMint(...).
     *      _safeMint calls onERC721Received on contract recipients — that is an external
     *      callback into untrusted code. Any state mutation placed after that call
     *      becomes reentrancy-exposed (a malicious recipient can observe a stale status
     *      and re-enter confirm/buy/cancel on this receipt before the write commits).
     *      Tested by ZuCityReentrancy.t.sol::test_confirm_ceiOrdering_statusWrittenBeforeMint.
     *      If you ever add a write below _safeMint, add a nonReentrant modifier first.
     */
    function _confirm(uint256 receiptId, address recipient, address manager, IReceiptValidator receiptValidator)
        internal
        returns (bool)
    {
        // Auto-confirm if: no receiptValidator (everyone allowed), caller is manager/officer,
        //                  or receiptValidator validates both the receipt and the buyer.
        if (
            address(receiptValidator) == address(0) || _isManagerOrRole(manager)
                || _safeValidate(receiptValidator, receiptId, msg.sender)
        ) {
            receipts[receiptId].status = ReceiptStatus.Accepted;
            emit ZuCitySystemLibrary.ConfirmReservation(receiptId, recipient, msg.sender);
            // External call LAST — onERC721Received on a contract recipient is untrusted code.
            _safeMint(recipient, receiptId);
            return true;
        }

        return false;
    }

    /// @notice Gas-budgeted, manually-decoded wrapper for the two untrusted, manager-supplied validator calls.
    /// @dev MAX_COMMUNITY_TOKENS=20 on the 1st gen ReceiptValidator gives a worst-case honest
    ///      gas cost of ~44k for validateBuyer; 100_000 provides ~2x headroom for more advanced checks.
    ///     Malicious validators that revert, OOG-mid-call, or return malicious garbage data return false.
    ///      the receipt stays Pending and user funds remain escrowed and recoverable via cancel().
    ///
    ///      Uses low-level staticcall + manual length+decode rather than try/catch because
    ///      Solidity's try/catch does not reliably catch ABI-decode failures from
    ///      maliciously-truncated return data (only call-level reverts).
    function _safeValidate(IReceiptValidator v, uint256 receiptId, address buyer) internal view returns (bool) {
        bytes memory cd1 = abi.encodeWithSelector(IReceiptValidator.validateReceipt.selector, receipts[receiptId]);
        (bool ok, bytes memory data) = address(v).staticcall{gas: 100_000}(cd1);
        if (!ok || data.length != 32 || !abi.decode(data, (bool))) return false;

        bytes memory cd2 = abi.encodeWithSelector(IReceiptValidator.validateBuyer.selector, buyer);
        (ok, data) = address(v).staticcall{gas: 100_000}(cd2);
        return ok && data.length == 32 && abi.decode(data, (bool));
    }

    /**
     * @notice Allows receipt recipient, item manager, or Immigration Officer to cancel a receipt.
     *             Unblocks dates in bitmap calendar if receipt is for a scarce item.
     *             Receipt MAY be canceled while Pending or Accepted.
     *             Full cancel fee is charged is receipt is Accepted, half fee is charged if it is only Pending.
     */
    function cancel(uint256 receiptId) external nonReentrant {
        Receipt memory b = receipts[receiptId];
        address manager = items[b.listingId].manager;

        if (msg.sender != b.recipient && !_isManagerOrRole(manager)) {
            revert Unauthorized();
        }

        if (b.status < ReceiptStatus.Canceled) {
            // status = accepted or pending = ok
            unchecked {
                // referrer always keeps fee for facilitating
                // and refund only comes out of manager pools so deduct
                uint256 refundable = b.totalPaid - b.referrerFee;
                // only pay half fee rate if hasnt been accepted yet
                uint256 fee = (refundable * uint256(cancelFeeBps))
                    / ((b.status == ReceiptStatus.Pending ? 2 : 1) * ZuCitySystemLibrary.BPS_DENOM);
                uint256 refund = refundable - fee;

                uint256 reserve = tokenReserves[manager][b.token];
                if (reserve < refund) revert InsufficientPayment();
                tokenReserves[manager][b.token] = reserve - refund;

                if (!items[b.listingId].unlimited) {
                    ZuCityCalendar.unreserveReceipt(availabilityCalendar, b);
                }
                receipts[receiptId].status = ReceiptStatus.Canceled;
                emit ZuCitySystemLibrary.CancelReservation(receiptId, b.recipient, msg.sender, refund, fee);

                SafeTransferLib.safeTransfer(b.token, b.recipient, refund);
            }
        } else {
            revert ReceiptAlreadyFinalized();
        }
    }

    /**
     * Receipt Fulfillment functions
     */

    /**
     * @notice Allows item manager and Immigration Officer
     * @param receiptId - the receipt that is being fulfilled
     */
    function fulfill(uint256 receiptId) public {
        _assertItemManagerOrOffice(receipts[receiptId].listingId);

        Receipt storage b = receipts[receiptId];
        if (b.status == ReceiptStatus.Pending) {
            confirm(receiptId); // auto confirm them for easier manager UX
        } else if (b.status == ReceiptStatus.Accepted) {} else {
            revert ReceiptAlreadyFinalized();
        }

        b.status = ReceiptStatus.Fulfilled;
        emit ZuCitySystemLibrary.Fulfill(receiptId, msg.sender);
    }

    /**
     *  @notice Allows item managers and Immigration Officer to fulfill
     *             a request while also returning all user funds.
     *             This lets users to reserve dates and stake their commitment without manager accepting payment.
     *             No cancel fees are charged. Referral fees are retained and excluded from refund amount
     * @param receiptId - the receipt that is being fulfilled
     * @return refund - amount of tokens returned to user.
     */
    function fulfillWithRefund(uint256 receiptId) external nonReentrant returns (uint256) {
        fulfill(receiptId);
        // send refund back after redemption complete to prevent double spend
        Receipt memory b = receipts[receiptId];
        unchecked {
            address manager = items[b.listingId].manager;
            uint256 refund = b.totalPaid - b.referrerFee;

            uint256 reserve = tokenReserves[manager][b.token];
            if (reserve < refund) revert InsufficientPayment();
            tokenReserves[manager][b.token] = reserve - refund;

            emit ZuCitySystemLibrary.FulfillWithRefund(receiptId, msg.sender, manager, refund);

            SafeTransferLib.safeTransfer(b.token, b.recipient, refund);
            return refund;
        }
    }

    /**
     * @notice allow manager an Immigration Officers to give items away to
     *     people without them reserving/paying/staking
     * @param b - Receipt data for the requested gift
     * @return id The receipt ID of the gifted item
     */
    function gift(Receipt calldata b) external nonReentrant returns (uint256) {
        _assertItemManagerOrOffice(b.listingId);
        uint256 id = _makeReceipt(b);
        // zero out payments to ensure no exploit potential by Immigration Officers
        receipts[id].totalPaid = 0;
        receipts[id].referrerFee = 0;
        // manager/officer gifts are auto-confirmed
        address manager = items[b.listingId].manager;
        _confirm(id, b.recipient, manager, managerConfigs[manager].receiptValidator);
        return id;
    }

    // Manager & Immigration Officer config functions
    /// @notice ban a user network-wide until a deadline
    function ban(address user, uint256 until) external {
        if (until < block.timestamp) revert InvalidBanDeadline();
        if (user == owner()) revert RecipientBan(); // cant ban admin and prevent critical functions
        if (!_isManagerOrRole(owner())) revert Unauthorized();

        bans[user] = until;
        emit ZuCitySystemLibrary.Ban(user, until, msg.sender);
    }

    /// @notice Set or update a manager's receiptValidator (used by all of their items at confirm/discount time).
    /// @dev Always writes to managerConfigs[msg.sender]; safe to call without any prior state and
    ///      without owning any items. Payment token is per-item now and is set via list() or updateItemPrice().
    function updateManagerConfig(ManagerConfig calldata config) external {
        managerConfigs[msg.sender] = config;
        emit ZuCitySystemLibrary.SetManagerConfig(msg.sender, address(config.receiptValidator));
    }

    function updateManagerRenderer(address _renderer) external {
        managerRenderer[msg.sender] = INFTRenderer(_renderer);
        emit ZuCitySystemLibrary.ManagerRendererUpdated(msg.sender, address(_renderer));
    }

    function updateManagerImmigration(address officer, bool canManage) external {
        immigration[msg.sender][officer] = canManage;
        emit ZuCitySystemLibrary.ManagerImmigrationUpdated(msg.sender, address(officer), canManage);
    }

    /**
     * @notice Allows item manager to update price AND payment token on a single item.
     *             Existing receipts snapshot their token at buy time (Receipt.token), so
     *             switching here only affects future buys; outstanding refunds still pay out
     *             in the original token.
     * @dev MAX_UINT = delisted
     *         MAX_UINT - 1 = free to get with offchain application process
     * @param id - item id to update price on
     * @param token - ERC20 future buyers must pay in
     * @param price - new item price denominated in `token` decimals
     */
    function updateItemPrice(uint64 id, address token, uint128 price) external {
        _assertOnlyManager(id);
        if (price == 0) revert ItemNeedsPrice();
        if (token == address(0)) revert InvalidToken();

        items[id].token = token;
        items[id].minUnitPrice = price;
        emit ZuCitySystemLibrary.UpdateItemPrice(id, token, price);
    }

    /**
     * @notice Allows item manager to update the transferability of a single item.
     *             true = receipts NFTs are tradable. false = soulbound
     * @param id - item id to update transferability
     * @param isTrans - whether or not item should be transferable
     *
     */
    function updateItemTransferrable(uint64 id, bool isTrans) external {
        _assertOnlyManager(id);
        items[id].transferable = isTrans;
        emit ZuCitySystemLibrary.UpdateItemTransferability(id, isTrans);
    }

    /// @notice Propose a new manager for an item (2-step transfer)
    function proposeItemManager(uint64 id, address newManager) external {
        _assertOnlyManager(id);
        if (newManager == address(0)) revert InvalidItemManager();
        pendingItemManager[id] = newManager;
        emit ZuCitySystemLibrary.ProposeItemManager(id, newManager);
    }

    /// @notice Accept management of a proposed item.
    /// @dev Does NOT require the accepter to have any managerConfig in place — token lives on the
    ///      item now, so a brand-new manager can take over without a setup tx. If they want a
    ///      different payment token or receiptValidator they can change those after acceptance.
    function acceptItemManager(uint64 id) external {
        if (pendingItemManager[id] != msg.sender) revert InvalidItemManager();
        items[id].manager = msg.sender;
        delete pendingItemManager[id];
        emit ZuCitySystemLibrary.AcceptItemManager(id, msg.sender);
    }

    /// @notice Withdraw tokens from reserves to a specified recipient
    /// @dev if manager banned they cant withdraw funds to ensure users can cancel receipts
    /// @param token The token to withdraw from reserves
    /// @param to The address to send `token` to
    /// @param amount The amount of `token` to withdraw
    function sink(address token, address to, uint256 amount) external nonReentrant {
        // manager cant exfiltrate funds after banned to ensure guests can cancel
        if (_isBanned(msg.sender)) revert ManagerBanned();
        if (to == address(0)) revert RecipientBan();
        if (to == address(this)) revert RecipientBan();

        tokenReserves[msg.sender][token] -= amount;
        emit ZuCitySystemLibrary.Sink(msg.sender, token, to, amount);

        SafeTransferLib.safeTransfer(token, to, amount);
    }

    function increaseReserves(address manager, address token, uint256 amount) external nonReentrant {
        uint256 currentBal = tokenReserves[manager][token];
        // anyone can deposit but only to a manager that accepts the token as payment already.
        if (currentBal == 0) revert InvalidToken();

        tokenReserves[manager][token] += amount;
        emit ZuCitySystemLibrary.ReservesIncreased(manager, token, msg.sender, amount);

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    /// ZuCity Network Config

    function updateReferrerFee(uint16 newBps) external onlyOwner {
        if (newBps > 20_00) revert ReferrerFeeTooHigh(); // cap split at 20%
        referrerFeeBps = newBps;
    }

    function updateCancelFee(uint16 newBps) external onlyOwner {
        if (newBps > ZuCitySystemLibrary.BPS_DENOM) revert CancelFeeTooHigh(); // cap slashing at 100%
        cancelFeeBps = newBps;
    }

    /**
     * @notice Rescue ETH accidentally sent to the contract
     * @dev Dont support arbitrary ERC20 tokens because logic too complicated
     *         with various managers and payment tokens
     *
     *
     */
    function rescueETH(address to) external onlyOwner {
        SafeTransferLib.safeTransferAllETH(to);
    }

    // Helpers for contract and UI

    /// @notice Check if caller is the manager or is their immigration officer
    function _isManagerOrRole(address manager) internal view returns (bool) {
        if (_isBanned(manager)) return false; // if manager is banned all ops by anyone are blocked
        // ^ this blocks admins from fulfill(), cancel(), gift().
        // receipt.recipient can still buy() and cancel().
        return manager == msg.sender || immigration[manager][msg.sender];
    }

    function _assertItemManagerOrOffice(uint64 itemId) internal view {
        if (!_isManagerOrRole(items[itemId].manager)) revert InvalidItemManager();
    }

    function _assertOnlyManager(uint64 itemId) internal view {
        if (_isBanned(msg.sender)) revert RecipientBan(); // if manager is banned all ops by anyone are blocked
        if (msg.sender != items[itemId].manager) revert InvalidItemManager();
    }

    /// @notice Check if caller (user or manager) is banned to disable item/receipt functionality.
    function _isBanned(address caller) internal view returns (bool) {
        return bans[caller] > block.timestamp;
    }

    function isAvailable(ReceiptDates memory dates) public view returns (bool) {
        return ZuCityCalendar.isAvailable(availabilityCalendar, dates);
    }

    function getPriceAndDiscountRate(Receipt[] calldata b, address buyer) external view returns (uint256, uint256) {
        return ZuCitySystemLibrary.getPriceAndDiscountRate(items, managerConfigs, b, buyer);
    }

    /// @dev for offchain reads of registry. Use idStartIndex for pagination to prevent gas limit issues.
    function allItems(uint64 idStartIndex, address manager, uint8 itemType, uint8 year, uint16 segmentCount)
        external
        view
        returns (ItemDisplayData[] memory)
    {
        return ZuCitySystemLibrary.allItems(
            items,
            managerConfigs,
            availabilityCalendar,
            itemsCounter,
            idStartIndex,
            manager,
            itemType,
            year,
            segmentCount
        );
    }

    /**
     * @notice Allows filtering all receipts by a particular recipient, a particular status, both, or neither.
     * @dev for offchain reads of registry. Use idStartIndex for pagination to prevent gas limit issues.
     */
    function allReceipts(uint256 idStartIndex, uint64[] calldata itemFilter, address recipient, uint8 status)
        external
        view
        returns (ReceiptDisplayData[] memory)
    {
        return ZuCitySystemLibrary.allReceipts(receipts, receiptsCounter, idStartIndex, itemFilter, recipient, status);
    }

    /// @notice NFT token name
    function name() public pure virtual override returns (string memory) {
        return ZuCitySystemLibrary.NFT_NAME;
    }

    /// @notice NFT token symbol
    function symbol() public pure virtual override returns (string memory) {
        return ZuCitySystemLibrary.NFT_SYMBOL;
    }

    /// @notice NFT overrides for interop
    function _ownerOf(uint256 nftId) internal view virtual override returns (address) {
        return receipts[nftId].recipient;
    }

    function _beforeTokenTransfer(address from, address to, uint256 id) internal virtual override {
        // prevent banned members buying or selling on secondary market
        if (_isBanned(to) || _isBanned(from)) revert RecipientBan();

        // final states are immutable on the holder
        // prevent double spending NFTs by selling on NFT exchange after it becomes unfulfillable.
        // No reason to transfer once canceled/checkedin anyway
        if (receipts[id].status > ReceiptStatus.Accepted) {
            revert ReceiptNotTransferable();
        }

        // after preventative measures, always allow minting
        // (transferable check below applies only to secondary-market transfers)
        if (from == address(0)) return;

        if (!items[receipts[id].listingId].transferable) {
            revert ItemNotTransferable();
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 id) internal virtual override {
        // update receipt state variable of owner for NFT and ZuCity System tracking
        receipts[id].recipient = to;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        if (receipts[id].recipient == address(0)) return "";
        INFTRenderer renderer = managerRenderer[items[receipts[id].listingId].manager];
        INFTRenderer defaultRenderer = managerRenderer[owner()];
        if (address(renderer) == address(0)) {
            if (address(defaultRenderer) == address(0)) return "";
            return defaultRenderer.tokenURI(id, address(this));
        }

        // Wrap untrusted manager-supplied renderer to return default value.
        // A revert here could affect entire collection's display in wallets/marketplaces.
        try renderer.tokenURI(id, address(this)) returns (string memory uri) {
            return uri;
        } catch {
            if (address(defaultRenderer) == address(0)) return "";
            return defaultRenderer.tokenURI(id, address(this));
        }
    }

    /// @notice EIP-712 domain name and version
    function _domainNameAndVersion() internal pure override returns (string memory n, string memory v) {
        n = "ZuCitySystem";
        v = "1";
    }
}
