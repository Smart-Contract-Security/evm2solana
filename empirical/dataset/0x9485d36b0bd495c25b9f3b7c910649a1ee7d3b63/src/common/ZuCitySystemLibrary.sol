// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {IReceiptValidator} from "../interfaces/IReceiptValidator.sol";
import {
    ReceiptStatus,
    ItemType,
    ManagerConfig,
    Item,
    Receipt,
    ItemDisplayData,
    ReceiptDisplayData,
    DiscountParams,
    ReceiptMasks,
    ReceiptDates,
    InsufficientPayment,
    InvalidGuest,
    InvalidItemManager,
    InvalidBanDeadline,
    InvalidReceiptLength,
    InvalidReceiptDate,
    ReceiptAlreadyConfirmedOrCanceled,
    MixedManagers,
    MixedPaymentTokens,
    YearOutOfRange
} from "./ZuCityTypes.sol";
import {ZuCityCalendar} from "./ZuCityCalendar.sol";

library ZuCitySystemLibrary {
    uint16 internal constant BPS_DENOM = 100_00;

    // Pinned ERC-721 identity. Single source of truth for both ZuCitySystem.name()
    // /symbol() and any test that asserts on them, so the two cannot drift.
    string internal constant NFT_NAME = "ZuCity Japan Network";
    string internal constant NFT_SYMBOL = "ZUJP";

    // ──────────────────────────── Events ────────────────────────────

    event MakePayment(
        uint256 indexed receiptId,
        uint64 indexed itemId,
        address indexed referrer,
        uint256 minPurchasePrice,
        uint256 totalBidPrice,
        uint256 parentReceipt
    );
    event MakeReservation(
        uint256 indexed receiptId,
        uint64 indexed listingId,
        address indexed recipient,
        uint8 year,
        uint16 startDay,
        uint8 daysCount
    );
    event ConfirmReservation(uint256 indexed receiptId, address indexed recipient, address indexed caller);
    event CancelReservation(
        uint256 indexed receiptId,
        address indexed recipient,
        address indexed canceler,
        uint256 refund,
        uint256 cancelFee
    );
    event Fulfill(uint256 indexed receiptId, address indexed recipient);
    event FulfillWithRefund(
        uint256 indexed receiptId, address indexed recipient, address indexed manager, uint256 refund
    );
    event Ban(address indexed user, uint256 deadline, address indexed officer);

    event ListItem(
        uint64 indexed itemId,
        address indexed manager,
        uint8 indexed itemType,
        bool transferable,
        bool unlimited,
        address token,
        uint128 price
    );
    event UpdateItemPrice(uint64 indexed itemId, address indexed token, uint128 price);
    event UpdateItemTransferability(uint64 indexed itemId, bool transferable);

    event SetManagerConfig(address indexed manager, address receiptValidator);
    event ProposeItemManager(uint64 indexed itemId, address indexed newManager);
    event AcceptItemManager(uint64 indexed itemId, address indexed newManager);
    event DefaultRendererUpdated(address renderer);
    event ManagerRendererUpdated(address indexed manager, address renderer);
    event ManagerImmigrationUpdated(address indexed manager, address officer, bool canManage);
    event Sink(address indexed manager, address indexed token, address indexed to, uint256 amount);
    event ReservesIncreased(address indexed manager, address indexed token, address indexed by, uint256 amount);
    // ──────────────────────────── Pure Functions ────────────────────────────

    function validateReceipt(Receipt calldata b) internal pure {
        if (b.status != ReceiptStatus.Pending) revert ReceiptAlreadyConfirmedOrCanceled();
        if (b.recipient == address(0)) revert InvalidGuest();
        if (b.daysCount == 0) revert InvalidReceiptLength();
        // Days are 1-indexed: day 1 is first day of year, day 0 is invalid
        // valid days = 1 < x < 364 = 364 valid days = MAX_DAYS
        if (b.startDay == 0 || b.startDay > ZuCityCalendar.MAX_DAYS) revert InvalidReceiptDate();
        // Bound year well under uint8.max so dates.year + 1 cannot overflow
        // in ZuCityCalendar.calculateSplice and DefaultRewarder._normalizeToZDays
        if (b.year > ZuCityCalendar.MAX_BOOKABLE_YEAR) revert YearOutOfRange();
    }

    /// @dev Calculate price using receiptValidator discount or flat rate
    function getDiscountedPrice(DiscountParams memory discountData, IReceiptValidator receiptValidator)
        internal
        view
        returns (uint256)
    {
        return _safeDiscount(receiptValidator, discountData);
    }

    /// @notice Gas-budgeted, manually-decoded wrapper for the untrusted manager-supplied
    ///         IReceiptValidator.discount() call. Fail-closed: returns the full (undiscounted)
    ///         price on revert, OOG-mid-call, or oversize/short return data so a buggy/malicious
    ///         validator cannot brick buy() / bulkBuy() / getPriceAndDiscountRate.
    /// @dev Mirrors _safeValidate in ZuCitySystem so all three IReceiptValidator entry-points
    ///      share one trust posture: 100k gas budget, manual length check, no try/catch
    ///      (try/catch does not reliably catch ABI-decode failures from truncated return data).
    ///
    ///      IMPORTANT: a returned value > discountData.totalPrice is NOT capped here.
    ///      receiptValidators are an intentional surge / differential-pricing tool — managers
    ///      MAY return a "discount" above the listing's totalPrice. The buyer pays the higher
    ///      amount, it is stored on the receipt, and is fully refundable on cancel.
    function _safeDiscount(IReceiptValidator v, DiscountParams memory discountData) internal view returns (uint256) {
        if(address(v) == address(0)) return discountData.totalPrice;
        bytes memory cd = abi.encodeWithSelector(IReceiptValidator.discount.selector, discountData);
        (bool ok, bytes memory data) = address(v).staticcall{gas: 100_000}(cd);
        if (!ok || data.length != 32) return discountData.totalPrice;
        return abi.decode(data, (uint256));
    }

    /// @dev Get bulk price and discount rate for multiple receipts
    function getPriceAndDiscountRate(
        mapping(uint64 => Item) storage items,
        mapping(address => ManagerConfig) storage managerConfigs,
        Receipt[] calldata b,
        address buyer
    ) internal view returns (uint256, uint256) {
        if (b.length == 0) revert InvalidReceiptLength();

        uint256 fullPrice;
        uint16 totalQuantity;
        uint8 uniqueItemCount;
        Item storage first = items[b[0].listingId];
        address manager = first.manager;
        address paymentToken = first.token;

        for (uint256 i; i < b.length;) {
            uint64 listingId = b[i].listingId;
            if (manager != items[listingId].manager) revert MixedManagers();
            if (paymentToken != items[listingId].token) revert MixedPaymentTokens();
            fullPrice += items[listingId].minUnitPrice * b[i].daysCount;
            totalQuantity += b[i].daysCount;

            // Match bulkBuy semantics: unique listingIds drive bulk discount tier
            bool seen;
            unchecked {
                for (uint256 k; k < i; ++k) {
                    if (b[k].listingId == listingId) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) ++uniqueItemCount;
                ++i;
            }
        }

        IReceiptValidator nl = managerConfigs[manager].receiptValidator;
        uint256 discountedPrice = _safeDiscount(
            nl,
            DiscountParams({
                totalPrice: fullPrice, totalQuantity: totalQuantity, itemCount: uniqueItemCount, buyer: buyer
            })
        );
        // in BPS e.g. 25 == 0.25%. Return 0 discount rate if fullPrice is 0 (items don't exist)
        uint256 discountRate = fullPrice > 0 ? ((fullPrice - discountedPrice) * BPS_DENOM) / fullPrice : 0;
        return (discountedPrice, discountRate);
    }

    // ──────────────────────────── View Query Functions ────────────────────────────

    /// @dev for offchain reads of registry. Use idStartIndex for pagination to prevent gas limit issues.
    function allItems(
        mapping(uint64 => Item) storage items,
        mapping(address => ManagerConfig) storage managerConfigs,
        mapping(bytes32 => uint256) storage calendar,
        uint64 itemsCounter,
        uint64 idStartIndex,
        address manager,
        uint8 itemType,
        uint8 year,
        uint16 segmentCount
    ) internal view returns (ItemDisplayData[] memory) {
        // First pass: count matching items
        unchecked {
            uint256 count;
            for (uint64 i = idStartIndex; i < itemsCounter; i++) {
                if (manager != address(0) && items[i].manager != manager) continue;
                if (itemType != type(uint8).max && uint8(items[i].itemType) != itemType) continue;
                ++count;
            }

            // Second pass: populate array
            ItemDisplayData[] memory lists = new ItemDisplayData[](count);
            uint256 returnIndex;
            for (uint64 i = idStartIndex; i < itemsCounter; i++) {
                if (manager != address(0) && items[i].manager != manager) continue;
                if (itemType != type(uint8).max && uint8(items[i].itemType) != itemType) continue;
                Item storage item = items[i];
                ManagerConfig storage config = managerConfigs[item.manager];
                uint256[] memory reservations = new uint256[](segmentCount);
                bytes32[] memory segments = new bytes32[](segmentCount);

                // iszero() and OR for cheaper and faster gas on logic checks
                if (year == 0 || segmentCount == 0 || item.unlimited) {} else {
                    for (uint256 j; j < segmentCount;) {
                        // get each segment of reservation data from the start to final dates requested
                        bytes32 segment = keccak256(
                            abi.encodePacked(
                                i,
                                uint8(year + (j / ZuCityCalendar.MAX_SEGMENTS)),
                                uint256(j % ZuCityCalendar.MAX_SEGMENTS)
                            )
                        );
                        reservations[j] = calendar[segment];
                        segments[j] = segment;
                        ++j;
                    }
                }

                lists[returnIndex] = ItemDisplayData({
                    id: i,
                    minUnitPrice: item.minUnitPrice,
                    itemType: item.itemType,
                    transferable: item.transferable,
                    unlimited: item.unlimited,
                    manager: item.manager,
                    token: item.token,
                    receiptValidator: address(config.receiptValidator),
                    reservations: reservations,
                    segments: segments
                });

                ++returnIndex;
            }

            return lists;
        }
    }

    /// @notice allows filtering all receipts by a particular recipient, a particular status, both, or neither.
    /// @dev for offchain reads of registry. Use idStartIndex for pagination to prevent gas limit issues.
    function allReceipts(
        mapping(uint256 => Receipt) storage receipts,
        uint256 receiptsCounter,
        uint256 idStartIndex,
        uint64[] calldata itemFilter,
        address recipient,
        uint8 status
    ) internal view returns (ReceiptDisplayData[] memory) {
        bool filterByItem = itemFilter.length > 0 && itemFilter[0] != type(uint64).max;

        // First pass: count matching receipts
        unchecked {
            uint256 count;
            for (uint256 i = idStartIndex; i < receiptsCounter; i++) {
                if (recipient != address(0) && receipts[i].recipient != recipient) continue;
                if (status != type(uint8).max && uint8(receipts[i].status) != status) continue;
                if (filterByItem && !_containsItem(itemFilter, receipts[i].listingId)) continue;
                ++count;
            }

            // Second pass: populate array
            ReceiptDisplayData[] memory lists = new ReceiptDisplayData[](count);
            uint256 idx;
            for (uint256 i = idStartIndex; i < receiptsCounter; i++) {
                Receipt memory re = receipts[i];
                if (recipient != address(0) && re.recipient != recipient) continue;
                if (status != type(uint8).max && uint8(re.status) != status) continue;
                if (filterByItem && !_containsItem(itemFilter, re.listingId)) continue;

                lists[idx] = ReceiptDisplayData({
                    listingId: re.listingId,
                    status: re.status,
                    year: re.year,
                    startDay: re.startDay,
                    daysCount: re.daysCount,
                    totalPaid: re.totalPaid,
                    recipient: re.recipient,
                    referrerFee: re.referrerFee,
                    token: re.token,
                    receiptId: i
                });
                ++idx;
            }

            return lists;
        }
    }

    function _containsItem(uint64[] calldata items, uint64 id) private pure returns (bool) {
        for (uint256 i; i < items.length;) {
            if (items[i] == id) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }
}
