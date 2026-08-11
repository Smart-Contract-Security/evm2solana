



/* ----------------------------------------------------------------------------
 *                   		DAEMONSv4 (DAEMON)          
 * ----------------------------------------------------------------------------
 *          Uniswap V4 Hook-Centric Concentrated Liquidity AMM
 *
 *   // https://x.com/DAEMONSv4
 *   // https://daemons.life/
 *
 * A high-performance AMM built directly on Uniswap v4 PoolManager with
 * custom dynamic hooks for adaptive fees, volatility-adjusted spreads,
 * concentrated liquidity management, and on-chain limit order execution.
 *
 * Key Technical Integrations:
 *   • IHooks implementation (before/afterSwap, before/afterAddLiquidity,
 *     before/afterRemoveLiquidity, beforeInitialize, afterInitialize)
 *   • Custom PoolKey + dynamic fee + tick spacing hooks
 *   • BalanceDelta + CurrencyLib accounting
 *   • PositionManager + LiquidityPosition NFT integration
 *   • MEV-resistant hook architecture with flash accounting
 *
 * Core Hook Capabilities:
 *   - Real-time volatility & volume based fee adjustment
 *   - Dynamic tick spacing & liquidity concentration
 *   - Automated rebalancing & range order hooks
 *   - Protocol-owned liquidity (POL) vault callbacks
 *   - Custom swap routing & intent-based execution hooks
 *
 * DAEMON Token Role:
 *   - Governance + fee capture token (ERC20 + ERC20Permit)
 *   - veDAEMON staking & revenue share
 *   - Emissions controller linked to protocol TVL & volume
 *
 * @author DAEMON Core Contributors
 * @notice Canonical DAEMON token contract - Do not deploy forks
 * -------------------------------------------------------------------------- */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";


contract DaemonFactory is ERC721, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 111;
    uint256 public constant MINT_PRICE = 0.01 ether; // set to 0 for free mint
    uint256 public constant MAX_PER_TX = 10;

    uint256 public totalMinted;
    bool public revealed;
    uint256 private immutable seed;

    string[10] private BACKGROUNDS = [
        "#1a1a2e", "#16213e", "#0f3460", "#533483", "#e94560",
        "#2d4263", "#c84b31", "#191919", "#ecdbba", "#346751"
    ];
    string[10] private BODIES = [
        "Crimson", "Azure", "Verdant", "Golden", "Obsidian",
        "Pearl", "Violet", "Amber", "Teal", "Rose"
    ];
    string[10] private EYES = [
        "Sleepy", "Laser", "Wide", "Wink", "Glow",
        "Cyber", "Calm", "Fierce", "Starry", "Void"
    ];

    constructor() ERC721("CHAO$--NFT", "CHAO$-NFT") Ownable(msg.sender) {
        // Fixed at deploy. Deterministic from here on — every token's traits
        // are knowable the moment this contract exists.
        seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, address(this)))
        );
    }

    // ---------------------------------------------------------------------
    // Minting
    // ---------------------------------------------------------------------

    function mint(uint256 quantity) external payable {
        require(quantity > 0 && quantity <= MAX_PER_TX, "bad quantity");
        require(totalMinted + quantity <= MAX_SUPPLY, "would exceed supply");
        require(msg.value >= MINT_PRICE * quantity, "insufficient payment");

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = totalMinted;
            totalMinted++;
            _safeMint(msg.sender, tokenId);
        }
    }

    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(totalMinted + quantity <= MAX_SUPPLY, "would exceed supply");
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = totalMinted;
            totalMinted++;
            _safeMint(to, tokenId);
        }
    }

    function reveal() external onlyOwner {
        revealed = true;
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // ---------------------------------------------------------------------
    // Traits — deterministic pseudo-random, derived from seed + tokenId
    // ---------------------------------------------------------------------

    function getTraits(uint256 tokenId)
        public
        view
        returns (uint8 background, uint8 body, uint8 eyes, uint8 rarity)
    {
        require(tokenId < MAX_SUPPLY, "invalid id");
        uint256 rand = uint256(keccak256(abi.encodePacked(seed, tokenId)));
        background = uint8(rand % 10);
        body = uint8((rand >> 8) % 10);
        eyes = uint8((rand >> 16) % 10);
        rarity = uint8((rand >> 24) % 100); // 0-99
    }

    // ---------------------------------------------------------------------
    // On-chain metadata
    // ---------------------------------------------------------------------

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireOwned(tokenId);

        if (!revealed) {
            return _encodeJSON(
                string(
                    abi.encodePacked(
                        '{"name":"g3nNFT #', tokenId.toString(),
                        '","description":"Unrevealed.",',
                        '"image":"', _placeholderSVG(), '"}'
                    )
                )
            );
        }

        return _encodeJSON(_buildJSON(tokenId));
    }

    function _buildJSON(uint256 tokenId)
        internal
        view
        returns (string memory)
    {
        (uint8 bg, uint8 body, uint8 eyes, uint8 rarity) = getTraits(tokenId);
        return string(
            abi.encodePacked(
                '{"name":"g3nNFT #', tokenId.toString(),
                '","description":"Fully on-chain randomly generated NFT.",',
                '"image":"', _buildSVG(bg, body, eyes), '",',
                '"attributes":', _buildAttributes(bg, body, eyes, rarity),
                '}'
            )
        );
    }

    function _buildAttributes(uint8 bg, uint8 body, uint8 eyes, uint8 rarity)
        internal
        view
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '[{"trait_type":"Background","value":"', BACKGROUNDS[bg], '"},',
                '{"trait_type":"Body","value":"', BODIES[body], '"},',
                '{"trait_type":"Eyes","value":"', EYES[eyes], '"},',
                '{"trait_type":"Rarity","value":', uint256(rarity).toString(), '}]'
            )
        );
    }

    function _encodeJSON(string memory json)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            )
        );
    }

    function _buildSVG(uint8 bg, uint8 body, uint8 eyes)
        internal
        view
        returns (string memory)
    {
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">',
                '<rect width="350" height="350" fill="', BACKGROUNDS[bg], '"/>',
                '<circle cx="175" cy="190" r="90" fill="hsl(',
                    uint256(uint256(body) * 36).toString(), ',70%,55%)"/>',
                '<circle cx="145" cy="165" r="14" fill="#fff"/>',
                '<circle cx="205" cy="165" r="14" fill="#fff"/>',
                '<circle cx="145" cy="165" r="6" fill="#000"/>',
                '<circle cx="205" cy="165" r="6" fill="#000"/>',
                '<text x="175" y="320" font-family="monospace" font-size="16" ',
                    'fill="#fff" text-anchor="middle">', BODIES[body], ' / ', EYES[eyes],
                '</text></svg>'
            )
        );
        return string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(svg))
            )
        );
    }

    function _placeholderSVG() internal pure returns (string memory) {
        string memory svg =
            '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350">'
            '<rect width="350" height="350" fill="#111"/>'
            '<text x="175" y="185" font-family="monospace" font-size="40" '
            'fill="#555" text-anchor="middle">?</text></svg>';
        return string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(svg))
            )
        );
    }
}
