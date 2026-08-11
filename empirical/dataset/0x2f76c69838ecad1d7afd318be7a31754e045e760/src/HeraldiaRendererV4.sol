// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IHeraldiaRenderer } from "./interfaces/IHeraldiaRenderer.sol";
import { Heraldia } from "./Heraldia.sol";
import { IHeraldiaStorage } from "./interfaces/IHeraldiaStorage.sol";
import { HeraldiaTraits } from "./HeraldiaTraitsV2.sol";
import { HeraldiaPreviewV2 } from "./HeraldiaPreviewV2.sol";
import { HeraldiaArtSelection } from "./HeraldiaArtSelection.sol";
import { HeraldiaArtSelectionV2 } from "./HeraldiaArtSelectionV2.sol";
import { HeraldiaAutoRevolve } from "./HeraldiaAutoRevolve.sol";
import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { Lifebuoy } from "solady/utils/Lifebuoy.sol";
import { Base64 } from "solady/utils/Base64.sol";
import { LibString } from "solady/utils/LibString.sol";

contract HeraldiaRendererV4 is IHeraldiaRenderer, OwnableBasic, Lifebuoy {
    using LibString for uint256;

    Heraldia               public heraldiaContract;
    IHeraldiaStorage       public storageContract;
    HeraldiaArtSelection   public artSelectionV1;
    HeraldiaArtSelectionV2 public artSelectionV2;
    HeraldiaAutoRevolve    public autoRevolve;

    address public colorWrapper;

    constructor(
        Heraldia _heraldia,
        IHeraldiaStorage _storage,
        HeraldiaArtSelection _artSelectionV1,
        HeraldiaArtSelectionV2 _artSelectionV2,
        HeraldiaAutoRevolve _autoRevolve
    ) OwnableBasic() Lifebuoy() {
        heraldiaContract = _heraldia;
        storageContract  = _storage;
        artSelectionV1   = _artSelectionV1;
        artSelectionV2   = _artSelectionV2;
        autoRevolve      = _autoRevolve;
    }

    // ─── Structs ──────────────────────────────────────────────────────────────

    struct TimeMachineData {
        bool    isActive;
        bytes32 customHash;
        bool    isV2;
        uint256 transfersRemaining;
        uint256 artTimestamp;
    }

    struct AutoRevolveData {
        bool    isActive;
        bytes32 dHash;
        string  intervalName;
    }

    // ─── tokenURI ─────────────────────────────────────────────────────────────

    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        address currentOwner  = heraldiaContract.ownerOf(tokenId);
        bytes32 staticHash    = storageContract.getStaticHash(tokenId);
        uint256 transferCount = storageContract.getTransferCount(tokenId);

        // Priority 1: Auto-Revolve
        AutoRevolveData memory ar = _resolveAutoRevolve(tokenId, currentOwner);

        bytes32 dHash;
        TimeMachineData memory tm;

        if (ar.isActive) {
            dHash = ar.dHash;
            tm = TimeMachineData({ isActive: false, customHash: bytes32(0), isV2: false, transfersRemaining: 0, artTimestamp: 0 });
        } else {
            // Priority 2 & 3: Time Machine
            tm = _resolveTimeMachine(tokenId);
            dHash = tm.isActive
                ? tm.customHash
                : keccak256(abi.encodePacked(currentOwner, tokenId));
        }

        HeraldiaTraits.TokenTraits memory traits = HeraldiaTraits.resolveTraits(staticHash, dHash, 0);

        (string memory svg, uint8 edgeTouchIndex) = HeraldiaPreviewV2.render(
            staticHash, dHash, traits, colorWrapper
        );
        traits.edgeTouchIndex = edgeTouchIndex;

        string memory svgB64     = Base64.encode(bytes(svg));
        string memory attributes = _buildAttributes(traits, transferCount, tm, ar);

        string memory json = string(abi.encodePacked(
            '{"name":"Heraldia #', tokenId.toString(), '",',
            '"description":"Heraldia dynamic generative art by ab83. Computed on-chain. Lives forever.",',
            '"image":"data:image/svg+xml;base64,', svgB64, '",',
            '"attributes":', attributes,
            '}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    // ─── Auto-Revolve ─────────────────────────────────────────────────────────

    function _resolveAutoRevolve(uint256 tokenId, address currentOwner) internal view returns (AutoRevolveData memory ar) {
        HeraldiaAutoRevolve.RevolveConfig memory cfg = autoRevolve.getConfig(tokenId);

        if (!cfg.enabled || cfg.wallet != currentOwner) {
            return AutoRevolveData({ isActive: false, dHash: bytes32(0), intervalName: "" });
        }

        uint256 rotations = (block.timestamp - cfg.startedAt) / cfg.intervalSeconds;
        bytes32 dHash = keccak256(abi.encodePacked(cfg.wallet, tokenId, rotations, cfg.startedAt));

        return AutoRevolveData({
            isActive:     true,
            dHash:        dHash,
            intervalName: _intervalName(cfg.interval)
        });
    }

    function _intervalName(HeraldiaAutoRevolve.RevolveInterval interval) internal pure returns (string memory) {
        if (interval == HeraldiaAutoRevolve.RevolveInterval.Daily)        return "Daily";
        if (interval == HeraldiaAutoRevolve.RevolveInterval.Every3Days)   return "Every 3 Days";
        if (interval == HeraldiaAutoRevolve.RevolveInterval.Every5Days)   return "Every 5 Days";
        if (interval == HeraldiaAutoRevolve.RevolveInterval.Weekly)       return "Weekly";
        if (interval == HeraldiaAutoRevolve.RevolveInterval.Monthly)      return "Monthly";
        if (interval == HeraldiaAutoRevolve.RevolveInterval.FiveMinutes)  return "Daily";
        return "";
    }

    // ─── Time Machine ─────────────────────────────────────────────────────────

    function _resolveTimeMachine(uint256 tokenId) internal view returns (TimeMachineData memory tm) {
        (
            bool isActive,
            bytes32 customHash,
            ,
            uint256 transfersRemaining,
            uint256 artTimestamp
        ) = artSelectionV2.getSelectionData(tokenId);

        if (isActive) {
            return TimeMachineData({
                isActive:           true,
                customHash:         customHash,
                isV2:               true,
                transfersRemaining: transfersRemaining,
                artTimestamp:       artTimestamp
            });
        }

        (bool isActiveV1, bytes32 customHashV1) = artSelectionV1.getActiveHash(tokenId);

        if (isActiveV1) {
            return TimeMachineData({
                isActive:           true,
                customHash:         customHashV1,
                isV2:               false,
                transfersRemaining: 1,
                artTimestamp:       0
            });
        }

        return TimeMachineData({
            isActive:           false,
            customHash:         bytes32(0),
            isV2:               false,
            transfersRemaining: 0,
            artTimestamp:       0
        });
    }

    // ─── Attributes ───────────────────────────────────────────────────────────

    function _buildAttributes(
        HeraldiaTraits.TokenTraits memory traits,
        uint256 transferCount,
        TimeMachineData memory tm,
        AutoRevolveData memory ar
    ) internal pure returns (string memory) {

        string memory autoRevolveTrait = '';
        if (ar.isActive) {
            autoRevolveTrait = string(abi.encodePacked(
                '{"trait_type":"Auto-Revolve","value":"', ar.intervalName, '"},'
            ));
        }

        string memory backToFuture = '';
        if (tm.isActive && tm.isV2 && tm.artTimestamp > 0) {
            string memory dateStr = _timestampToDate(tm.artTimestamp);
            backToFuture = string(abi.encodePacked(
                '{"trait_type":"Back to the Future","value":"', dateStr, '"},'
            ));
        }

        string memory timeMachine = '';
        if (tm.isActive) {
            string memory tmValue = tm.transfersRemaining == 1
                ? 'Last Transfer'
                : string(abi.encodePacked(tm.transfersRemaining.toString(), ' Transfers Left'));
            timeMachine = string(abi.encodePacked(
                '{"trait_type":"Time Machine","value":"', tmValue, '"},'
            ));
        }

        return string(abi.encodePacked(
            '[',
            autoRevolveTrait,
            backToFuture,
            timeMachine,
            '{"trait_type":"Theme","value":"',
            HeraldiaTraits.getThemeName(traits.isDarkTheme), '"},',
            '{"trait_type":"Background","value":"',
            HeraldiaTraits.getBackgroundName(traits.bgIndex), '"},',
            '{"trait_type":"Emblem","value":"',
            HeraldiaTraits.getEmblemName(traits.sizeIndex, traits.edgeTouchIndex), '"},',
            '{"trait_type":"Emblem Style","value":"',
            HeraldiaTraits.getStyleName(traits.styleIndex), '"},',
            '{"trait_type":"Pattern","value":"',
            HeraldiaTraits.getPatternName(traits.patternIndex), '"},',
            '{"trait_type":"Transfers","value":"',
            HeraldiaTraits.getTransferGroup(transferCount), '"}',
            ']'
        ));
    }

    // ─── Date helpers ─────────────────────────────────────────────────────────

    function _timestampToDate(uint256 timestamp) internal pure returns (string memory) {
        uint256 z   = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 y   = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp  = (5 * doy + 2) / 153;
        uint256 d   = doy - (153 * mp + 2) / 5 + 1;
        uint256 m   = mp < 10 ? mp + 3 : mp - 9;
        if (m <= 2) y++;
        return string(abi.encodePacked(
            _monthName(m), ' ', d.toString(), ' ', y.toString()
        ));
    }

    function _monthName(uint256 m) internal pure returns (string memory) {
        if (m == 1)  return "Jan";
        if (m == 2)  return "Feb";
        if (m == 3)  return "Mar";
        if (m == 4)  return "Apr";
        if (m == 5)  return "May";
        if (m == 6)  return "Jun";
        if (m == 7)  return "Jul";
        if (m == 8)  return "Aug";
        if (m == 9)  return "Sep";
        if (m == 10) return "Oct";
        if (m == 11) return "Nov";
        return "Dec";
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function setHeraldiaContract(address _heraldia) external onlyOwner {
        heraldiaContract = Heraldia(_heraldia);
    }

    function setStorageContract(address _storage) external onlyOwner {
        storageContract = IHeraldiaStorage(_storage);
    }

    function setArtSelectionV1(address _v1) external onlyOwner {
        artSelectionV1 = HeraldiaArtSelection(_v1);
    }

    function setArtSelectionV2(address _v2) external onlyOwner {
        artSelectionV2 = HeraldiaArtSelectionV2(_v2);
    }

    function setAutoRevolve(address _autoRevolve) external onlyOwner {
        autoRevolve = HeraldiaAutoRevolve(_autoRevolve);
    }

    function setColorWrapper(address _colorWrapper) external onlyOwner {
        colorWrapper = _colorWrapper;
    }
}
