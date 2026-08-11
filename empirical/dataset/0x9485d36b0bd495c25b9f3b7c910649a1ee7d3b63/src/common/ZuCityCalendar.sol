// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {ReceiptMasks, ReceiptDates, Receipt, ItemAlreadyReserved} from "./ZuCityTypes.sol";
import {ZuCitySystemLibrary} from "./ZuCitySystemLibrary.sol";

library ZuCityCalendar {
    // Bitmap Calendar Constants

    /**
     * @notice Amount of days (bits) available per calendar segment storage
     *         Each segment uses bits 0 to (DAYS_PER_SEGMENT - 1) of a uint256 to store reservation data
     * @dev Day counters are 1-indexed: day 1 = Jan 1st and 0th bit. Day 364 = Dec 30th and 363rd bit.
     *
     */
    uint16 internal constant DAYS_PER_SEGMENT = 182;

    /**
     * @notice Amount of segments per year in intergalactic calendar.
     *             This deterimines total amount of days available for booking
     *
     * @dev Day's segment = (day - 1) / DAYS_PER_SEGMENT
     *         Day's bit in segment = (day - 1) % DAYS_PER_SEGMENT
     */
    uint8 internal constant MAX_SEGMENTS = 2;

    /**
     * @notice MAX_SEGMENTS * DAYS_PER_SEGMENT.
     * 2 segments)
     * @dev Current config means New Years Eve and leap day are NOT bookable every year.
     *         new years eve = free day that doesnt require payment if booking spans annual segments.
     *         Ensure client does proper calculations.
     */
    uint16 internal constant MAX_DAYS = 364;

    // Maximum year storable in a receipt (~ Earth year 2203).
    // All write-path entry points (buy/bulkBuy/gift via validateReceipt) enforce this.
    uint8 constant MAX_BOOKABLE_YEAR = 180;

    // ──────────────────────────── Pure Functions ────────────────────────────
    /**
     * @notice Calculates the storage keys and bitmasks for any duration of receipt booking.
     *             Segment layout with DAYS_PER_SEGMENT=182 and MAX_SEGMENTS=2:
     *             Segment 0: days 1-182   (182 days, bits 0-181)
     *             Segment 1: days 183-364 (182 days, bits 0-181)
     *             Days are 1-indexed: day 1 = first day of year, day 365 = last day
     *             Each segment stores DAYS_PER_SEGMENT days in a uint256 bitmap
     *             Formula: segment = (day - 1) / DAYS_PER_SEGMENT
     *             Formula: bit = (day - 1) % DAYS_PER_SEGMENT
     * @dev IMPORTANT - algorithm logic depends on totalDays being uint8 with maximum 255 value being < MAX_DAYS
     * @dev Bitmap Calendar Architecture (1-indexed days):
     *         Segment 0: days 1-182   (bits 0-181)
     *         Segment 1: days 183-364 (bits 0-181)
     *         Storage key = keccak256(listingId, year, segmentIndex)
     *         Supports N segments per year automatically based on DAYS_PER_SEGMENT
     * @param dates The receipt dates containing listingId, year, startDay (1-indexed), and daysCount
     * @return masks The calculated storage keys (k1, k2) and bitmasks (m1, m2)
     */
    function calculateSplice(ReceiptDates memory dates) internal pure returns (ReceiptMasks memory masks) {
        unchecked {
            // Convert 1-indexed day to 0-indexed for bitmap math
            // Day 1 → index 0, Day 365 → index 364
            uint256 dayIndex = dates.startDay - 1;

            // Calculate segment index: which segment does this day belong to?
            // Day 1:   (1-1)/182 = 0 → segment 0
            // Day 182: (182-1)/182 = 0 → segment 0
            // Day 183: (183-1)/182 = 1 → segment 1
            // Day 364: (363-1)/182 = 2 → segment 2
            uint256 segmentIndex = dayIndex / DAYS_PER_SEGMENT;

            // Calculate bit position within the segment's bitmap
            // Day 1:   (1-1)%182 = 0   → bit 0 in segment 0
            // Day 182: (182-1)%182 = 181 → bit 181 in segment 0
            // Day 183: (183-1)%182 = 0   → bit 0 in segment 1
            uint256 localStart = dayIndex % DAYS_PER_SEGMENT;

            // Generate unique storage key for this listing's calendar segment
            masks.k1 = keccak256(abi.encodePacked(dates.listingId, dates.year, segmentIndex));

            // Calculate how many days remain in this segment from localStart
            // Note: daysRemainingInSegment is always <= daysRemainingInYear, so we only need segment capacity check
            uint256 daysRemainingInSegment = DAYS_PER_SEGMENT - localStart;

            if (dates.daysCount <= daysRemainingInSegment) {
                // All requested days fit within current segment
                // Mask formula: Create daysCount consecutive 1-bits, shift to localStart position
                // Example: 3 days at bit 5 → ((1<<3)-1)<<5 = 0b111<<5 = 0b11100000
                // masks.m1 = ((1 << dates.daysCount) - 1) << localStart;
                masks.m1 = (type(uint256).max >> (256 - dates.daysCount)) << localStart;
            } else {
                // Booking spans into next segment/year - need two masks
                // m1: Fill remaining days in current segment
                // masks.m1 = ((1 << daysRemainingInSegment) - 1) << localStart;
                masks.m1 = (type(uint256).max >> (256 - daysRemainingInSegment)) << localStart;

                // m2: Overflow days start at bit 0 of next segment
                // masks.m2 = (1 << (dates.daysCount - daysRemainingInSegment)) - 1;
                masks.m2 = (type(uint256).max >> (256 - (dates.daysCount - daysRemainingInSegment)));

                // Determine which segment/year the overflow goes to
                // @DEV this algo assumes that there are MAX_SEGMENTS = 2 segments so hardcode 0 and 1
                if (segmentIndex >= MAX_SEGMENTS - 1) {
                    // In last segment → overflow to next year's segment 0
                    // @DEV we cap dates.year to MAX_BOOKABLE_YEAR. If allowed to uint8 max then need overflow check here
                    masks.k2 = keccak256(abi.encodePacked(dates.listingId, dates.year + 1, uint256(0)));
                } else {
                    // Not in last segment → overflow to next segment same year
                    masks.k2 = keccak256(abi.encodePacked(dates.listingId, dates.year, uint256(1)));
                }
            }
        }
    }

    // ──────────────────────────── View Functions ────────────────────────────

    function checkAvailability(mapping(bytes32 => uint256) storage calendar, ReceiptMasks memory m)
        internal
        view
        returns (bool)
    {
        // all dates requested must be empty.
        // Logic: CalMap = CalMap AND Mask
        // If CalMap = 1111 and Mask = 0010 (middle bit reserved)
        // then &Mask = 0010 != 0 (CONFLICT)
        // 1001 & 0110 = 0000 (NO CONFLICT)
        if ((calendar[m.k1] & m.m1) != 0) return false;
        if (m.m2 > 0) {
            if ((calendar[m.k2] & m.m2) != 0) return false;
        }
        return true;
    }

    function isAvailable(mapping(bytes32 => uint256) storage calendar, ReceiptDates memory dates)
        internal
        view
        returns (bool)
    {
        // Validate inputs - days are 1-indexed
        if (dates.startDay == 0 || dates.startDay > MAX_DAYS) return false;
        if (dates.daysCount == 0) return false;
        if (dates.year > MAX_BOOKABLE_YEAR) return false;

        ReceiptMasks memory masks = calculateSplice(dates);
        return checkAvailability(calendar, masks);
    }

    // ──────────────────────────── Storage-Mutating Functions ────────────────────────────

    function reserveReceipt(mapping(bytes32 => uint256) storage calendar, Receipt memory b) internal {
        ReceiptMasks memory masks = calculateSplice(ReceiptDates(b.listingId, b.year, b.startDay, b.daysCount));

        if (!checkAvailability(calendar, masks)) revert ItemAlreadyReserved();

        // Logic: CalMap = CalMap OR Mask (set reserved bits)
        calendar[masks.k1] |= masks.m1;
        if (masks.m2 > 0) {
            calendar[masks.k2] |= masks.m2;
        }
        // MakeReservation event emitted by caller (_makeReceiptAt) which has the receipt ID
    }

    function unreserveReceipt(mapping(bytes32 => uint256) storage calendar, Receipt memory b) internal {
        ReceiptMasks memory m = calculateSplice(ReceiptDates(b.listingId, b.year, b.startDay, b.daysCount));

        // Logic: CalMap = CalMap AND (NOT Mask)
        // If CalMap = 1111 and Mask = 0010 (middle bit reserved)
        // then ~Mask = 1101
        // 1111 & 1101 = 1101 (Middle bit cleared to 0)
        calendar[m.k1] &= ~m.m1;

        if (m.m2 > 0) {
            calendar[m.k2] &= ~m.m2;
        }
        // CancelReservation event emitted by caller (cancel) which has the receipt ID
    }
}
