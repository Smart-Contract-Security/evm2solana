// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {IReceiptValidator} from "../interfaces/IReceiptValidator.sol";

// ──────────────────────────── Enums ────────────────────────────

/// @notice Lifecycle status of a Receipt.
/// @dev Transitions: Pending → Accepted → Fulfilled, or Pending/Accepted → Canceled.
enum ReceiptStatus {
    /// @notice Receipt has been bought but not yet confirmed by the item manager / validator.
    Pending,
    /// @notice Receipt has been confirmed: NFT is minted to recipient.
    Accepted,
    /// @notice Receipt has been canceled by the buyer or manager; funds refunded (minus cancel fee).
    Canceled,
    /// @notice Product / service  represented by the receipt has been delivered. Terminal state.
    Fulfilled
}

/// @notice The kind of thing being sold. Drives how an item is interpreted by the UI and (in some cases) reservation rules.
/// @dev `itemType` on an Item is immutable after listing.
enum ItemType {
    /// @notice Single-event admission (e.g. a day pass, a workshop seat).
    Ticket,
    /// @notice Recurring / long-lived access (e.g. monthly or lifetime membership).
    Membership,
    /// @notice Sponsorship slot — a brand/individual buying visibility within an event or network.
    Sponsorship,
    /// @notice One-of-a-kind or limited-edition artwork.
    Art,
    /// @notice Physical and digital merchandise (apparel, prints, swag).
    Merch,
    /// @notice Off-chain service unit (e.g. consulting, compute units).
    Service,
    /// @notice A single bookable room within a property.
    Room,
    /// @notice A multi-room apt/suite/condo within a property.
    Suite,
    /// @notice A whole-property rental.
    Villa,
    /// @notice A bookable event/community space (e.g. coworking floor, gallery, courtyard).
    Venue,
    /// @notice Rentable hardware / gear (e.g. cameras, projectors, instruments).
    Equipment
}

// ──────────────────────────── Structs ────────────────────────────

/// @notice Per-manager configuration applied to all items they list.
/// @dev Stored in `managerConfigs[manager]`. Mutable by the manager via `updateManagerConfig`.
struct ManagerConfig {
    /// @notice Optional gate that decides if a Receipt becomes Accepted on confirm() and computes per-buyer discounts.
    ///         When unset (address(0)), confirms succeed unconditionally and no discount is applied.
    IReceiptValidator receiptValidator;
}

/// @notice A listing in the ZuCity catalog. Created by `list(Item)` and indexed by an auto-incrementing `id`.
/// @dev `itemType` and `unlimited` are immutable after listing; `minUnitPrice`, `token`, `transferable`,
///      and `manager` can be updated via the manager-only setters.
struct Item {
    /// @notice Minimum price per unit, denominated in `token`'s smallest unit.
    ///         A "unit" is 1 item when `unlimited == true`, or 1 item/day when `unlimited == false`.
    ///         Sentinel `type(uint128).max`     ⇒ delisted (not buyable).
    ///         Sentinel `type(uint128).max - 1` ⇒ off-chain application required (not buyable on-chain).
    uint128 minUnitPrice;
    /// @notice Kind of thing being sold. Immutable after listing.
    ItemType itemType;
    /// @notice If true, the minted Receipt NFT can be transferred between wallets; if false, Receipt is soulbound.
    ///        Can be toggled anytime after listing.
    bool transferable;
    /// @notice If true, supply is uncapped (e.g. tickets, merch). If false, the item is calendar-bookable
    ///         and a single unit is reserved per day. Immutable after listing.
    bool unlimited;
    // 13 bytes left in slot 1
    /// @notice ERC20 used for payment. Mutable via `updateItemPrice`. Used to support managers listing
    ///         the same item across multiple stablecoins / chains.
    address token;
    /// @notice Address that receives payments on confirm() and whose `ManagerConfig.receiptValidator`
    ///         and immigration[manager] officers gate buyer confirmations and cancelations.
    address manager;
    // 12 bytes left in slot 2
}

/// @notice Read-friendly view of an Item plus runtime data (reservations, calendar segments, validator).
///         Returned by `allItems(...)`. Never written on-chain.
struct ItemDisplayData {
    /// @notice itemsCounter() when list() was called (key into `items`).
    uint64 id;
    /// @notice Minimum price per unit; see `Item.minUnitPrice` for sentinel semantics.
    uint128 minUnitPrice;
    /// @notice Kind of thing being sold.
    ItemType itemType;
    /// @notice Receipt NFT transferability flag.
    bool transferable;
    /// @notice Whether supply is uncapped (true) or calendar-bookable (false).
    bool unlimited;
    // Slot 1 end
    /// @notice ERC20 used for payment.
    address token;
    /// @notice Address receiving payments on confirm().
    address manager;
    /// @notice Manager's currently configured validator (zero address if none).
    address receiptValidator;
    /// @notice Bookings keyed by year — packed bitmap reservations for the calendar segments requested.
    /// @dev Same shape as `availabilityCalendar` values. Empty when `unlimited == true`.
    uint256[] reservations;
    /// @notice Calendar segment keys aligned 1:1 with `reservations`.
    bytes32[] segments;
}

/// @notice On-chain record of a purchase. Storage struct backing each Receipt NFT.
/// @dev Indexed by `receiptId` in `receipts`. Manager is intentionally NOT cached: if `Item.manager`
///      changes between buy() and cancel/fulfill, the new manager is responsible for refunds.
struct Receipt {
    /// @notice Listing id this receipt was purchased against (key into `items`).
    uint64 listingId;
    /// @notice Current lifecycle status. See `ReceiptStatus`.
    ReceiptStatus status;
    /// @notice Year offset, 0-indexed from 2023 (so year 0 = 2023, year 1 = 2024, …, year Z = 2023+Z).
    uint8 year;
    /// @notice Start day of the stay/booking within the year (0..364). For `unlimited` items, ignored.
    uint16 startDay;
    /// @notice Number of consecutive days reserved starting at `startDay`. Max 255.
    ///         For unlimited items it is raw quantity of items requested.
    uint8 daysCount;
    /// @notice Total amount paid by the buyer in `token`'s smallest unit. May exceed the listed minimum
    ///         (overbid) to make acceptance more likely during high season times.
    uint128 totalPaid;
    // Slot 0: 64+8+8+16+8+128 = 232 bits
    /// @notice Address that receives the Receipt NFT if accepted. Allows gifting / proxy purchases.
    address recipient;
    // Slot 1: 160 bits
    /// @notice Portion of `totalPaid` that has been routed to the referrer. Already included in `totalPaid`
    ///         (do not double-count). Set when the buy completes.
    uint128 referrerFee;
    // Slot 2: 128 bits
    /// @notice Payment token at the time of purchase. Cached so cancel/refund always use the original token
    ///         even if the manager switches `Item.token` or manager changes.
    address token;
    // Slot 3: 160 bits
    /// @dev manager not cached in receipt. If item manager changes,
    ///      new manager responsible  to fund refunds
}

/// @notice Read-friendly view of a Receipt that also carries its on-chain `receiptId`.
///         Returned by `allReceipts(...)`; never written on-chain.
struct ReceiptDisplayData {
    /// @notice Listing id this receipt was purchased against.
    uint64 listingId;
    /// @notice Current lifecycle status.
    ReceiptStatus status;
    /// @notice Year offset, 0-indexed to 2023.
    uint8 year;
    /// @notice Start day within the year (0..364).
    uint16 startDay;
    /// @notice Number of consecutive days reserved.
    uint8 daysCount;
    /// @notice Total amount paid by the buyer (includes referrer fee).
    uint128 totalPaid;
    /// @notice Address that receives the Receipt NFT if accepted.
    address recipient;
    /// @notice Referrer fee portion of `totalPaid` (already included; do not sum).
    uint128 referrerFee;
    /// @notice Payment token used at purchase time.
    address token;
    /// @dev manager not cached in receipt. If item manager changes,
    ///      new manager responsible  to fund refunds
    /// @notice The on-chain receipt id (key into `receipts`).
    uint256 receiptId;
    // ReceiptMasks mask; // can compute already from data in receipt to make cheaper for onchain calls that only want to read.
}

/// @notice Stack-optimization carrier for calendar bitmap masks; passed between internal functions
///         to avoid recomputing reservation keys.
/// @dev Not user-facing; never returned by an external function. Internal-helper struct only.
struct ReceiptMasks {
    /// @notice Calendar segment key for the first overlapped segment.
    bytes32 k1;
    /// @notice Bitmap mask of days the receipt occupies within segment k1.
    uint256 m1;
    /// @notice Calendar segment key for the second overlapped segment (when the booking spans two segments);
    ///         zero bytes when only one segment is touched.
    bytes32 k2;
    /// @notice Bitmap mask of days the receipt occupies within segment k2 (zero when unused).
    uint256 m2;
}

/// @notice Stack-optimization carrier for the date-range portion of a Receipt; passed to availability
///         checks without copying the full Receipt.
/// @dev Mirrors the date fields of `Receipt`. Used by `isAvailable(...)`.
struct ReceiptDates {
    /// @notice Listing id whose availability is being queried.
    uint64 listingId;
    /// @notice Year offset, 0-indexed to 2023.
    uint8 year;
    /// @notice Start day within the year (0..364).
    uint16 startDay;
    /// @notice Number of consecutive days requested. Max 255.
    uint8 daysCount;
}

/// @notice Data forwarded to a manager's `IReceiptValidator` so it can compute a buyer-specific discount.
/// @dev Aggregated across a single buy() / bulkBuy() call.
struct DiscountParams {
    /// @notice Pre-discount total price summed across all receipts in the call, in payment-token units.
    uint256 totalPrice;
    /// @notice Number of receipts (items) in the call. Max 255.
    uint8 itemCount;
    /// @notice Total day-units reserved (sum of `daysCount`) across the call.
    /// @dev uint16 max = 65,535 ≥ 255 (max daysCount) × 257, so cannot overflow within a single call.
    uint16 totalQuantity;
    /// @notice The address paying / receiving the discount.
    address buyer;
}

// ──────────────────────────── Errors ────────────────────────────

/// @notice Sent value or `totalPaid` was below the required price (including any applied discount).
error InsufficientPayment();
/// @notice Receipt recipient is the zero address or otherwise rejected by validator rules.
error InvalidGuest();
/// @notice Caller is not the manager of the referenced item.
error InvalidItemManager();
/// @notice Ban `until` timestamp is in the past or otherwise unacceptable.
error InvalidBanDeadline();
/// @notice `daysCount` is zero or exceeds the protocol's max segment length.
error InvalidReceiptLength();
/// @notice `year`/`startDay`/`daysCount` violate calendar bounds (e.g. cross past Z-year, exceed 364).
error InvalidReceiptDate();
/// @notice confirm()/cancel() called on a receipt that is no longer Pending.
error ReceiptAlreadyConfirmedOrCanceled();
/// @notice fulfill() called on a receipt that is already Canceled or Fulfilled.
error ReceiptAlreadyFinalized();
/// @notice Transfer attempted on a Receipt whose Item is non-transferable (soulbound).
error ReceiptNotTransferable();
/// @notice Manager attempted to flip an item to transferable that is structurally non-transferable.
error ItemNotTransferable();
/// @notice bulkBuy() received receipts whose summed payment does not match the provided value.
error InvalidBulkPayment();
/// @notice list()/updateItemPrice() called with price equal to zero where a positive price is required.
error ItemNeedsPrice();
/// @notice The requested calendar slot is already reserved.
error ItemAlreadyReserved();
/// @notice Manager set a referrer fee BPS above the protocol-enforced ceiling.
error ReferrerFeeTooHigh();
/// @notice Manager set a cancel fee BPS above the protocol-enforced ceiling.
error CancelFeeTooHigh();
/// @notice Recipient address is currently banned from receiving receipts.
error RecipientBan();
/// @notice The item's manager is currently banned and cannot accept new business.
error ManagerBanned();
/// @notice bulkBuy() received receipts spanning more than one manager — must be split into separate calls.
error MixedManagers();
/// @notice bulkBuy() received receipts denominated in more than one token — must be split into separate calls.
error MixedPaymentTokens();
/// @notice Provided ERC20 token address is not a valid / accepted payment token.
error InvalidToken();
/// @notice An operation that requires validator-approval was attempted on a receipt that wasn't validated.
error ReceiptNotReceiptValidatored();
/// @notice Caller is not a validator and is attempting a validator-only operation.
error CallerNotReceiptValidatored();
/// @notice Computed year offset exceeds the supported range (8-bit, 0-indexed to 2023).
error YearOutOfRange();
