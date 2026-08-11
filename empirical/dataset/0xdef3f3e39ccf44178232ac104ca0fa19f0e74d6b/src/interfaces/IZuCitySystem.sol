// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {INFTRenderer} from "./INFTRenderer.sol";
import {IReceiptValidator} from "./IReceiptValidator.sol";
import {
    ManagerConfig,
    Item,
    Receipt,
    ItemDisplayData,
    ReceiptDisplayData,
    ReceiptDates,
    ReceiptStatus,
    ItemType
} from "../common/ZuCityTypes.sol";

interface IZuCitySystem {
    // Owner functions - network config
    function list(Item calldata l) external returns (uint64);
    function ban(address user, uint256 until) external;
    function updateReferrerFee(uint16 newBps) external;
    function updateCancelFee(uint16 newBps) external;

    // Core user/manager functions
    function buy(Receipt calldata b, address referrer) external returns (uint256, uint256);
    function bulkBuy(Receipt[] calldata reservations, address referrer) external returns (uint256, uint256[] memory);
    function confirm(uint256 _receiptId) external returns (bool);
    function cancel(uint256 _receiptId) external;
    function fulfill(uint256 _receiptId) external;
    function fulfillWithRefund(uint256 receiptId) external returns (uint256);

    // Manager gifting & payment withdrawals
    function gift(Receipt calldata b) external returns (uint256);
    function sink(address token, address to, uint256 amount) external;

    // Manager config
    function updateManagerConfig(ManagerConfig calldata config) external;
    function updateManagerRenderer(address _renderer) external;
    function updateItemPrice(uint64 id, address token, uint128 price) external;
    function updateItemTransferrable(uint64 id, bool isTrans) external;
    function proposeItemManager(uint64 id, address newManager) external;
    function acceptItemManager(uint64 id) external;

    // View functions
    function isAvailable(ReceiptDates memory dates) external view returns (bool);
    function getPriceAndDiscountRate(Receipt[] calldata b, address buyer) external view returns (uint256, uint256);
    function allItems(uint64 idStartIndex, address manager, uint8 itemType, uint8 year, uint16 segmentCount)
        external
        view
        returns (ItemDisplayData[] memory);
    function allReceipts(uint256 idStartIndex, uint64[] calldata itemFilter, address recipient, uint8 status)
        external
        view
        returns (ReceiptDisplayData[] memory);

    // State variables (auto-generated getters)
    function cancelFeeBps() external view returns (uint16);
    function referrerFeeBps() external view returns (uint16);
    // function itemsCounter() external view returns (uint64);
    function receiptsCounter() external view returns (uint256);
    function availabilityCalendar(bytes32 key) external view returns (uint256);
    function tokenReserves(address manager, address token) external view returns (uint256);
    function receipts(uint256 id)
        external
        view
        returns (
            uint64 listingId,
            ReceiptStatus status,
            uint8 year,
            uint16 startDay,
            uint8 daysCount,
            uint128 totalPaid,
            address recipient,
            uint128 referrerFee,
            address token
        );
    function items(uint64 id)
        external
        view
        returns (
            uint128 minUnitPrice,
            ItemType itemType,
            bool transferable,
            bool unlimited,
            address token,
            address manager
        );
    function bans(address user) external view returns (uint256);
    function pendingItemManager(uint64 id) external view returns (address);
    function managerConfigs(address manager) external view returns (IReceiptValidator receiptValidator);
    function managerRenderer(address manager) external view returns (INFTRenderer);
}
