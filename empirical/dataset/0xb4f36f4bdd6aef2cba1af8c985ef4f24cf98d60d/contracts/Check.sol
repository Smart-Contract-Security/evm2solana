// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC2981} from "solady/src/tokens/ERC2981.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface ITokenDistribution {
    function distribute(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

/**
 * @title Check
 * @notice Tradeable Check NFT holding a fixed gross METH allocation that decays
 * linearly per second from 1% payout at mint to 97% payout at 7 days, then caps.
 *
 *     payoutRate(t) = 1% + 96% * min(1, t / 7 days)
 *
 * The decay clock starts at mint and never resets. Checks are tradable; the
 * holder at redeem time receives the payout, the rest is burned via the
 * TokenDistributor. Pre-TGE Checks remain unredeemable until TGE is flagged
 * live, but the decay clock keeps ticking.
 */
contract Check is ERC721, Ownable, ERC2981 {
    using Strings for uint256;

    struct CheckData {
        uint128 grossMethAmount;
        uint64 createdAt;
        bool redeemed;
    }

    uint256 public constant DECAY_DURATION = 7 days;
    uint256 public constant MIN_RATE = 0.01e18;   // 1%
    uint256 public constant MAX_RATE = 0.97e18;   // 97%
    uint256 public constant RATE_DELTA = 0.96e18; // 96%
    uint256 public constant RATE_PRECISION = 1e18;

    address public miningSystem;
    address public tokenDistribution;
    bool public tgeLive;

    uint256 private _tokenIdCounter;
    mapping(uint256 => CheckData) public checks;

    /// @dev Single shared background for all checks (112x112 PNG, base64).
    string public checkBackground;

    /// @dev Check sprite images keyed by tier index (1..7), each a 71x35 PNG (base64).
    mapping(uint8 => string) public checkImages;

    event CheckMinted(uint256 indexed tokenId, address indexed to, uint256 grossMethAmount, uint256 createdAt);
    event CheckRedeemed(uint256 indexed tokenId, address indexed holder, uint256 payout, uint256 burned, uint256 effectiveRate);
    event TGEStatusUpdated(bool live);
    event MiningSystemUpdated(address indexed miningSystem);
    event TokenDistributionUpdated(address indexed tokenDistribution);
    event CheckBackgroundUpdated();
    event CheckImageUpdated(uint8 indexed tier);

    error OnlyMiningSystem();
    error CheckNotFound();
    error AlreadyRedeemed();
    error TGENotLive();
    error NotHolder();
    error ZeroAddress();
    error InvalidCheckTier();
    error InvalidArrayLength();

    constructor() ERC721("METH Check", "CHECK") Ownable(msg.sender) {
        _setDefaultRoyalty(msg.sender, 500);
    }

    modifier onlyMiningSystem() {
        if (msg.sender != miningSystem) revert OnlyMiningSystem();
        _;
    }

    /// @notice Mint a Check. Called by the MiningEthSystem on claim with METH-side > 0.
    function mintCheck(address to, uint256 grossMethAmount) external onlyMiningSystem returns (uint256) {
        if (grossMethAmount == 0) return 0;
        uint256 tokenId = ++_tokenIdCounter;
        _safeMint(to, tokenId);
        checks[tokenId] = CheckData({
            grossMethAmount: uint128(grossMethAmount),
            createdAt: uint64(block.timestamp),
            redeemed: false
        });
        emit CheckMinted(tokenId, to, grossMethAmount, block.timestamp);
        return tokenId;
    }

    /// @notice Redeem a Check for METH at the current per-second decay rate.
    function redeem(uint256 tokenId) external {
        if (!tgeLive) revert TGENotLive();
        address holder = _ownerOf(tokenId);
        if (holder == address(0)) revert CheckNotFound();
        if (holder != msg.sender) revert NotHolder();

        CheckData storage data = checks[tokenId];
        if (data.redeemed) revert AlreadyRedeemed();

        uint256 effectiveRate = _currentPayoutRate(data.createdAt);
        uint256 gross = data.grossMethAmount;
        uint256 payout = (gross * effectiveRate) / RATE_PRECISION;
        uint256 burned = gross - payout;

        data.redeemed = true;
        _burn(tokenId);

        if (payout > 0) {
            ITokenDistribution(tokenDistribution).distribute(holder, payout);
        }
        if (burned > 0) {
            ITokenDistribution(tokenDistribution).burn(burned);
        }

        emit CheckRedeemed(tokenId, holder, payout, burned, effectiveRate);
    }

    /// @notice Live decay rate for a Check at the current block timestamp.
    function currentPayoutRate(uint256 tokenId) public view returns (uint256) {
        CheckData memory data = checks[tokenId];
        if (data.createdAt == 0) revert CheckNotFound();
        return _currentPayoutRate(data.createdAt);
    }

    function _currentPayoutRate(uint64 createdAt) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - createdAt;
        if (elapsed >= DECAY_DURATION) return MAX_RATE;
        uint256 progress = (elapsed * RATE_PRECISION) / DECAY_DURATION;
        return MIN_RATE + (RATE_DELTA * progress) / RATE_PRECISION;
    }

    /// @notice Off-chain helper for frontends to preview redemption right now.
    function previewRedeem(uint256 tokenId)
        external
        view
        returns (uint256 payout, uint256 burned, uint256 effectiveRate)
    {
        CheckData memory data = checks[tokenId];
        if (data.createdAt == 0) revert CheckNotFound();
        effectiveRate = _currentPayoutRate(data.createdAt);
        payout = (uint256(data.grossMethAmount) * effectiveRate) / RATE_PRECISION;
        burned = uint256(data.grossMethAmount) - payout;
    }

    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // ━━━ On-chain metadata ━━━

    /**
     * @notice ERC721 metadata for `tokenId`, fully on-chain.
     *         The image composites the shared background with the tier sprite
     *         determined by the check's gross METH value. Reverts after a
     *         check is redeemed (since the underlying ERC721 is burned).
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert CheckNotFound();

        CheckData memory data = checks[tokenId];
        uint256 gross = uint256(data.grossMethAmount);
        uint8 tier = _selectCheckTier(gross);
        uint256 rate = _currentPayoutRate(data.createdAt);
        uint256 payout = (gross * rate) / RATE_PRECISION;
        uint256 burned = gross - payout;

        string memory image = _generateTokenImage(checkBackground, checkImages[tier]);
        string memory name = string(abi.encodePacked("METH Check #", tokenId.toString()));
        string memory description = _generateDescription(gross, rate, payout);
        string memory attributes = _generateAttributes(gross, tier, data.createdAt, rate, payout, burned);

        string memory json = string(abi.encodePacked(
            '{',
                '"name":"', name, '",',
                '"description":"', description, '",',
                '"image":"data:image/svg+xml;base64,', image, '",',
                '"external_url":"https://miningeth.tech",',
                '"attributes":', attributes,
            '}'
        ));

        return string(abi.encodePacked(
            'data:application/json;base64,',
            Base64.encode(bytes(json))
        ));
    }

    /**
     * @dev Pick the check sprite tier for a gross METH amount (1e18-scaled).
     *      under 25 → 1, under 50 → 2, under 100 → 3, under 250 → 4,
     *      under 500 → 5, under 1000 → 6, 1000+ → 7.
     */
    function _selectCheckTier(uint256 gross) internal pure returns (uint8) {
        if (gross < 25e18)   return 1;
        if (gross < 50e18)   return 2;
        if (gross < 100e18)  return 3;
        if (gross < 250e18)  return 4;
        if (gross < 500e18)  return 5;
        if (gross < 1000e18) return 6;
        return 7;
    }

    /**
     * @dev Compose a 112x112 SVG that paints the shared background and overlays
     *      the check sprite at its native pixel size, auto-centered via a
     *      flexbox-in-foreignObject. `image-rendering:pixelated` keeps pixel art
     *      crisp at any display scale.
     */
    function _generateTokenImage(
        string memory backgroundData,
        string memory foregroundData
    ) internal pure returns (string memory) {
        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 112 112" shape-rendering="crispEdges" style="image-rendering:pixelated">',
            '<image href="data:image/png;base64,', backgroundData, '" x="0" y="0" width="112" height="112"/>',
            '<foreignObject x="0" y="0" width="112" height="112">',
            '<div xmlns="http://www.w3.org/1999/xhtml" style="width:100%;height:100%;display:flex;align-items:center;justify-content:center">',
            '<img src="data:image/png;base64,', foregroundData, '" style="image-rendering:pixelated;display:block"/>',
            '</div>',
            '</foreignObject>',
            '</svg>'
        );
        return Base64.encode(svg);
    }

    function _generateDescription(uint256 gross, uint256 rate, uint256 payout) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "A METH Check worth ",
            _formatMeth(gross),
            " METH gross. Redeem now for ",
            _formatMeth(payout),
            " METH (",
            _formatRatePercent(rate),
            "%). Payout decays from 1% at mint to 97% over 7 days."
        ));
    }

    function _generateAttributes(
        uint256 gross,
        uint8 tier,
        uint64 createdAt,
        uint256 rate,
        uint256 payout,
        uint256 burned
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '[',
                '{"trait_type":"Gross Value","value":"', _formatMeth(gross), ' METH"},',
                '{"trait_type":"Tier","value":', Strings.toString(uint256(tier)), '},',
                '{"trait_type":"Payout Rate","value":"', _formatRatePercent(rate), '%"},',
                '{"trait_type":"Redeem Value","value":"', _formatMeth(payout), ' METH"},',
                '{"trait_type":"Burn Amount","value":"', _formatMeth(burned), ' METH"},',
                '{"display_type":"date","trait_type":"Minted","value":', Strings.toString(uint256(createdAt)), '}',
            ']'
        ));
    }

    /// @dev Render a 1e18-scaled METH amount with two decimals (e.g. 92.71).
    function _formatMeth(uint256 amount) internal pure returns (string memory) {
        uint256 cents = amount / 1e16; // 1 METH = 100 cents
        uint256 whole = cents / 100;
        uint256 frac = cents % 100;
        string memory fracStr = frac < 10
            ? string(abi.encodePacked("0", Strings.toString(frac)))
            : Strings.toString(frac);
        return string(abi.encodePacked(Strings.toString(whole), ".", fracStr));
    }

    /// @dev Render a 1e18-scaled rate as a percentage with two decimals
    ///      (e.g. 0.5e18 → "50.00", 0.9712e18 → "97.12").
    function _formatRatePercent(uint256 rate) internal pure returns (string memory) {
        uint256 bps = (rate * 10000) / RATE_PRECISION;
        uint256 whole = bps / 100;
        uint256 frac = bps % 100;
        string memory fracStr = frac < 10
            ? string(abi.encodePacked("0", Strings.toString(frac)))
            : Strings.toString(frac);
        return string(abi.encodePacked(Strings.toString(whole), ".", fracStr));
    }

    // ━━━ Admin ━━━

    function setMiningSystem(address _miningSystem) external onlyOwner {
        if (_miningSystem == address(0)) revert ZeroAddress();
        miningSystem = _miningSystem;
        emit MiningSystemUpdated(_miningSystem);
    }

    function setTokenDistribution(address _tokenDistribution) external onlyOwner {
        if (_tokenDistribution == address(0)) revert ZeroAddress();
        tokenDistribution = _tokenDistribution;
        emit TokenDistributionUpdated(_tokenDistribution);
    }

    function setTGELive(bool live) external onlyOwner {
        tgeLive = live;
        emit TGEStatusUpdated(live);
    }

    /// @notice Set the shared 112x112 check background (base64-encoded PNG).
    function setCheckBackground(string calldata imageData) external onlyOwner {
        checkBackground = imageData;
        emit CheckBackgroundUpdated();
    }

    /// @notice Set the sprite for a single tier (1..7).
    function setCheckImage(uint8 tier, string calldata imageData) external onlyOwner {
        if (tier < 1 || tier > 7) revert InvalidCheckTier();
        checkImages[tier] = imageData;
        emit CheckImageUpdated(tier);
    }

    /// @notice Batch-set tier sprites. Arrays must be the same length.
    function setCheckImageBatch(uint8[] calldata tiers, string[] calldata imageData) external onlyOwner {
        uint256 n = tiers.length;
        if (n != imageData.length) revert InvalidArrayLength();
        for (uint256 i = 0; i < n; i++) {
            uint8 tier = tiers[i];
            if (tier < 1 || tier > 7) revert InvalidCheckTier();
            checkImages[tier] = imageData[i];
            emit CheckImageUpdated(tier);
        }
    }

    // ━━━ Overrides ━━━

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
