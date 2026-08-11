// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {INFTRenderer} from "../interfaces/INFTRenderer.sol";
import {ZuCitySystem} from "../ZuCitySystem.sol";
import {ReceiptStatus, ItemType} from "../common/ZuCityTypes.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

contract ReceiptRenderer is INFTRenderer {
    using LibString for uint256;
    using LibString for address;

    function tokenURI(uint256 receiptId, address system) external view override returns (string memory) {
        ZuCitySystem sys = ZuCitySystem(system);

        (
            uint64 listingId,
            ReceiptStatus receiptStatus,
            uint8 year,
            uint16 startDay,
            uint8 daysCount,,,
            uint256 totalPaid,
            address token
        ) = sys.receipts(receiptId);

        (, ItemType itemTypeEnum, bool transferable,,, address manager) = sys.items(listingId);

        uint8 status = uint8(receiptStatus);
        uint8 itemType = uint8(itemTypeEnum);
        string memory tokenSymbol = _getTokenSymbol(token);

        string memory svg = _buildSVG(
            receiptId, uint256(listingId), status, year, startDay, daysCount, totalPaid, itemType, transferable, manager
        );

        string memory json = _buildJSON(
            receiptId,
            uint256(listingId),
            status,
            year,
            startDay,
            daysCount,
            totalPaid,
            tokenSymbol,
            itemType,
            transferable,
            svg
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ──────────────────────────── SVG Builder ────────────────────────────

    function _buildSVG(
        uint256 receiptId,
        uint256 listingId,
        uint8 status,
        uint8 year,
        uint16 startDay,
        uint8 daysCount,
        uint256 totalPaid,
        uint8 itemType,
        bool transferable,
        address manager
    ) internal pure returns (string memory) {
        return string.concat(
            _svgOpen(itemType),
            _svgHeader(receiptId, itemType),
            _svgStatus(status),
            _svgDates(year, startDay, daysCount),
            _svgPayment(totalPaid, listingId, transferable),
            _svgManager(manager),
            "</svg>"
        );
    }

    function _svgOpen(uint8 itemType) internal pure returns (string memory) {
        (string memory bgStart, string memory bgEnd) = _itemTypeColors(itemType);
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480' style='background:#1a1a2e'>",
            "<defs><linearGradient id='bg' x1='0' y1='0' x2='1' y2='1'>",
            "<stop offset='0%' stop-color='",
            bgStart,
            "'/>",
            "<stop offset='100%' stop-color='",
            bgEnd,
            "'/>",
            "</linearGradient></defs>",
            "<rect x='10' y='10' width='280' height='460' rx='16' fill='url(#bg)' opacity='0.15'/>",
            "<rect x='10' y='10' width='280' height='460' rx='16' fill='none' stroke='",
            bgStart,
            "' stroke-width='1.5' opacity='0.6'/>"
        );
    }

    function _svgHeader(uint256 receiptId, uint8 itemType) internal pure returns (string memory) {
        return string.concat(
            "<text x='30' y='50' font-family='monospace' font-size='11' fill='#888'>ZUCITY RECEIPT</text>",
            "<text x='30' y='75' font-family='monospace' font-size='24' font-weight='bold' fill='#fff'>#",
            receiptId.toString(),
            "</text>",
            "<text x='30' y='100' font-family='monospace' font-size='13' fill='#aaa'>",
            _itemTypeName(itemType),
            "</text>"
        );
    }

    function _svgStatus(uint8 status) internal pure returns (string memory) {
        string memory statusColor = _statusColor(status);
        return string.concat(
            "<rect x='30' y='120' width='120' height='26' rx='6' fill='",
            statusColor,
            "' opacity='0.2'/>",
            "<text x='90' y='138' font-family='monospace' font-size='11' fill='",
            statusColor,
            "' text-anchor='middle'>",
            _statusName(status),
            "</text>",
            "<line x1='30' y1='160' x2='270' y2='160' stroke='#333' stroke-width='0.5'/>"
        );
    }

    function _svgDates(uint8 year, uint16 startDay, uint8 daysCount) internal pure returns (string memory) {
        return string.concat(
            "<text x='30' y='185' font-family='monospace' font-size='10' fill='#666'>DATES</text>",
            "<text x='30' y='205' font-family='monospace' font-size='13' fill='#fff'>Year ",
            uint256(year).toString(),
            "</text>",
            "<text x='30' y='225' font-family='monospace' font-size='13' fill='#fff'>Day ",
            uint256(startDay).toString(),
            " - Day ",
            uint256(startDay + daysCount - 1).toString(),
            "</text>",
            "<text x='30' y='245' font-family='monospace' font-size='11' fill='#aaa'>",
            uint256(daysCount).toString(),
            daysCount == 1 ? " day" : " days",
            "</text>",
            "<line x1='30' y1='265' x2='270' y2='265' stroke='#333' stroke-width='0.5'/>"
        );
    }

    function _svgPayment(uint256 totalPaid, uint256 listingId, bool transferable)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "<text x='30' y='290' font-family='monospace' font-size='10' fill='#666'>PAYMENT</text>",
            "<text x='30' y='310' font-family='monospace' font-size='13' fill='#fff'>Paid: ",
            totalPaid.toString(),
            "</text>",
            "<text x='30' y='330' font-family='monospace' font-size='11' fill='#aaa'>Item #",
            listingId.toString(),
            "</text>",
            "<text x='30' y='350' font-family='monospace' font-size='11' fill='#aaa'>",
            transferable ? "Transferable" : "Non-transferable",
            "</text>",
            "<line x1='30' y1='370' x2='270' y2='370' stroke='#333' stroke-width='0.5'/>"
        );
    }

    function _svgManager(address manager) internal pure returns (string memory) {
        string memory addr = manager.toHexStringChecksummed();
        return string.concat(
            "<text x='30' y='395' font-family='monospace' font-size='10' fill='#666'>MANAGER</text>",
            "<text x='30' y='415' font-family='monospace' font-size='10' fill='#aaa'>",
            addr,
            "</text>",
            "<text x='30' y='455' font-family='monospace' font-size='9' fill='#444'>zucity.eth</text>"
        );
    }

    // ──────────────────────────── JSON Builder ────────────────────────────

    function _buildJSON(
        uint256 receiptId,
        uint256 listingId,
        uint8 status,
        uint8 year,
        uint16 startDay,
        uint8 daysCount,
        uint256 totalPaid,
        string memory tokenSymbol,
        uint8 itemType,
        bool transferable,
        string memory svg
    ) internal pure returns (string memory) {
        string memory svgBase64 = Base64.encode(bytes(svg));
        return string.concat(
            '{"name":"ZuCity Receipt #',
            receiptId.toString(),
            '","description":"ZuCity receipt for ',
            _itemTypeName(itemType),
            ' booking","image":"data:image/svg+xml;base64,',
            svgBase64,
            '","attributes":',
            _buildAttributes(
                listingId, status, year, startDay, daysCount, totalPaid, tokenSymbol, itemType, transferable
            ),
            "}"
        );
    }

    function _buildAttributes(
        uint256 listingId,
        uint8 status,
        uint8 year,
        uint16 startDay,
        uint8 daysCount,
        uint256 totalPaid,
        string memory tokenSymbol,
        uint8 itemType,
        bool transferable
    ) internal pure returns (string memory) {
        return string.concat(
            '[{"trait_type":"Item Type","value":"',
            _itemTypeName(itemType),
            '"},{"trait_type":"Status","value":"',
            _statusName(status),
            '"},{"trait_type":"Year","display_type":"number","value":',
            uint256(year).toString(),
            "},",
            _buildAttributesPart2(listingId, startDay, daysCount, totalPaid, tokenSymbol, transferable),
            "]"
        );
    }

    function _buildAttributesPart2(
        uint256 listingId,
        uint16 startDay,
        uint8 daysCount,
        uint256 totalPaid,
        string memory tokenSymbol,
        bool transferable
    ) internal pure returns (string memory) {
        return string.concat(
            '{"trait_type":"Start Day","display_type":"number","value":',
            uint256(startDay).toString(),
            '},{"trait_type":"Duration","display_type":"number","value":',
            uint256(daysCount).toString(),
            '},{"trait_type":"Total Paid","display_type":"number","value":',
            totalPaid.toString(),
            '},{"trait_type":"Token Symbol","value":"',
            tokenSymbol,
            '"},{"trait_type":"Listing ID","display_type":"number","value":',
            listingId.toString(),
            '},{"trait_type":"Transferable","value":"',
            transferable ? "Yes" : "No",
            '"}'
        );
    }

    // ──────────────────────────── Helpers ────────────────────────────

    function _itemTypeName(uint8 itemType) internal pure returns (string memory) {
        if (itemType == 0) return "Ticket";
        if (itemType == 1) return "Membership";
        if (itemType == 2) return "Sponsorship";
        if (itemType == 3) return "Art";
        if (itemType == 4) return "Merch";
        if (itemType == 5) return "Service";
        if (itemType == 6) return "Room";
        if (itemType == 7) return "Suite";
        if (itemType == 8) return "Villa";
        if (itemType == 9) return "Venue";
        if (itemType == 10) return "Equipment";
        return "Unknown";
    }

    function _statusName(uint8 status) internal pure returns (string memory) {
        if (status == 0) return "PENDING";
        if (status == 1) return "CONFIRMED";
        if (status == 2) return "CANCELED";
        if (status == 3) return "FULFILLED";
        return "UNKNOWN";
    }

    function _itemTypeColors(uint8 itemType) internal pure returns (string memory, string memory) {
        if (itemType == 0) return ("#4A90D9", "#2563EB"); // Ticket - blue
        if (itemType == 1) return ("#4A90D9", "#1E40AF"); // Membership - deep blue
        if (itemType == 2) return ("#4A90D9", "#1E40AF"); // Sponsorship - deep blue
        if (itemType == 3) return ("#E74C3C", "#DC2626"); // Art - red
        if (itemType == 4) return ("#F39C12", "#EA580C"); // Merch - orange
        if (itemType == 5) return ("#3B82F6", "#2563EB"); // Service - sky blue
        if (itemType == 6) return ("#7B68EE", "#6C3CE0"); // Room - purple
        if (itemType == 7) return ("#8B5CF6", "#7C3AED"); // Suite - violet
        if (itemType == 8) return ("#A855F7", "#9333EA"); // Villa - deep violet
        if (itemType == 9) return ("#2ECC71", "#16A34A"); // Venue - green
        if (itemType == 10) return ("#1ABC9C", "#0D9488"); // Equipment - teal
        return ("#888888", "#666666");
    }

    function _getTokenSymbol(address token) internal view returns (string memory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (success && data.length > 0) {
            return abi.decode(data, (string));
        }
        return "???";
    }

    function _statusColor(uint8 status) internal pure returns (string memory) {
        if (status == 0) return "#F59E0B"; // Pending - amber
        if (status == 1) return "#10B981"; // Confirmed - green
        if (status == 2) return "#EF4444"; // Canceled - red
        if (status == 3) return "#8B5CF6"; // Fulfilled - purple
        return "#888888";
    }
}
