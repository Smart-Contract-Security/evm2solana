// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract Cells is ERC721A, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant COST = 0.0001 ether;
    uint256 public constant MAX_PER_MINT = 100;
    
    mapping(address => bool) public hasFreeMinted;

    constructor() ERC721A("Genesis Cell", "CELL") Ownable() {}

    // Free mint (1 per wallet)
    function freeMint() external {
        require(!hasFreeMinted[msg.sender], "Already claimed free mint");
        require(_totalMinted() < MAX_SUPPLY, "Max supply reached");
        
        hasFreeMinted[msg.sender] = true;
        _mint(msg.sender, 1);
    }

    // Paid mint (max 10)
    function mint(uint256 quantity) external payable {
        require(quantity > 0 && quantity <= MAX_PER_MINT, "Invalid quantity");
        require(_totalMinted() + quantity <= MAX_SUPPLY, "Max supply reached");
        require(msg.value >= COST * quantity, "Insufficient payment");
        
        _mint(msg.sender, quantity);
    }

    // Withdraw to contract creator only
    function withdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    // Generate tokenURI with on-chain SVG
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        string memory svg = generateSVG(tokenId);
        string memory attributes = generateAttributes(tokenId);
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Cell #', tokenId.toString(), '",',
                        '"description": "Fully on-chain generative cell art",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": [', attributes, ']',
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function generateSVG(uint256 tokenId) internal pure returns (string memory) {
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId)));
        
        // Determine rarity and special effects
        uint256 rarityRoll = seed % 1000;
        bool isGlowing = rarityRoll < 20; // 2% chance
        bool isMonochrome = rarityRoll >= 20 && rarityRoll < 70; // 5% chance
        bool isPulsing = rarityRoll >= 70 && rarityRoll < 170; // 10% chance
        bool isRainbow = rarityRoll >= 170 && rarityRoll < 190; // 2% chance
        
        // Get colors
        (string memory bgColor, string memory bgStroke) = getCellColor(seed, 0, isMonochrome, isRainbow);
        
        string memory glowFilter = isGlowing ? 
            '<defs><filter id="glow"><feGaussianBlur stdDeviation="8" result="coloredBlur"/><feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>' : '';
        
        string memory pulseAnimation = isPulsing ? 
            '<animate attributeName="r" values="260;280;260" dur="3s" repeatCount="indefinite"/>' : '';
        
        return string(
            abi.encodePacked(
                '<svg width="600" height="600" viewBox="0 0 600 600" xmlns="http://www.w3.org/2000/svg">',
                glowFilter,
                '<circle cx="300" cy="300" r="260" fill="', bgColor, '" stroke="', bgStroke, '" stroke-width="8"',
                isGlowing ? ' filter="url(#glow)"' : '', '>',
                pulseAnimation,
                '</circle>',
                generateFloatingObjects(seed, isMonochrome, isRainbow, isGlowing),
                generateCentralCell(seed, isMonochrome, isRainbow, isGlowing, isPulsing),
                generateParticles(seed, isMonochrome, isRainbow),
                '</svg>'
            )
        );
    }

    function generateFloatingObjects(uint256 seed, bool isMonochrome, bool isRainbow, bool isGlowing) internal pure returns (string memory) {
        string memory objects = '';
        
        for (uint i = 0; i < 4; i++) {
            uint256 objSeed = uint256(keccak256(abi.encodePacked(seed, i)));
            (string memory fillColor, string memory strokeColor) = getObjectColor(objSeed, i, isMonochrome, isRainbow);
            
            uint256 cx = 180 + (objSeed % 300);
            uint256 cy = 150 + ((objSeed / 1000) % 300);
            uint256 r = 30 + (objSeed % 20);
            
            objects = string(abi.encodePacked(
                objects,
                '<g><circle cx="', uint256(cx).toString(), '" cy="', uint256(cy).toString(), 
                '" r="', uint256(r).toString(), '" fill="', fillColor, '" stroke="', strokeColor, '" stroke-width="3"',
                isGlowing ? ' filter="url(#glow)"' : '', '/>',
                '<animateTransform attributeName="transform" type="translate" values="0 0;', 
                getAnimationValues(objSeed), '" dur="', uint256(10 + (i * 2)).toString(), 's" repeatCount="indefinite"/>',
                '</g>'
            ));
        }
        
        return objects;
    }

    function generateCentralCell(uint256 seed, bool isMonochrome, bool isRainbow, bool isGlowing, bool isPulsing) internal pure returns (string memory) {
        (string memory outerColor, string memory innerColor) = getCentralColors(seed, isMonochrome, isRainbow);
        
        string memory pulseAnim = isPulsing ? 
            '<animate attributeName="r" values="75;85;75" dur="2s" repeatCount="indefinite"/>' : '';
        
        return string(abi.encodePacked(
            '<g><circle cx="300" cy="300" r="75" fill="', outerColor, '" stroke="', innerColor, '" stroke-width="4"',
            isGlowing ? ' filter="url(#glow)"' : '', '>',
            pulseAnim,
            '</circle>',
            '<circle cx="300" cy="300" r="30" fill="', innerColor, '"/>',
            '<animateTransform attributeName="transform" type="translate" values="0 0;10 -10;-10 15;0 0" dur="18s" repeatCount="indefinite"/>',
            '</g>'
        ));
    }

    function generateParticles(uint256 seed, bool isMonochrome, bool isRainbow) internal pure returns (string memory) {
        (string memory particleColor, ) = getObjectColor(seed, 10, isMonochrome, isRainbow);
        
        return string(abi.encodePacked(
            '<g fill="', particleColor, '">',
            '<circle cx="140" cy="250" r="8"/>',
            '<circle cx="480" cy="270" r="10"/>',
            '<circle cx="260" cy="470" r="7"/>',
            '<circle cx="360" cy="130" r="9"/>',
            '<animateTransform attributeName="transform" type="translate" values="0 0;15 10;-10 20;0 0" dur="8s" repeatCount="indefinite"/>',
            '</g>'
        ));
    }

    function getCellColor(uint256 seed, uint256 index, bool isMonochrome, bool isRainbow) internal pure returns (string memory, string memory) {
        if (isRainbow) {
            return ("#ff0080", "#8000ff");
        }
        if (isMonochrome) {
            uint256 gray = 200 + (seed % 55);
            return (toGrayScale(gray), toGrayScale(gray - 50));
        }
        
        string[20] memory bgColors = [
            "#dff7ff", "#ffe4e1", "#e1f5e1", "#fff9e1", "#f0e1ff",
            "#ffe1f5", "#e1ffff", "#fff0e1", "#e1e1ff", "#f5ffe1",
            "#ffe1e1", "#e1fff0", "#ffffe1", "#f0ffe1", "#e1f0ff",
            "#ffe1ff", "#f5e1ff", "#e1ffe1", "#ffffe1", "#e1ffef"
        ];
        
        string[20] memory strokes = [
            "#4a90c2", "#c24a4a", "#4ac24a", "#c2c24a", "#904ac2",
            "#c24a90", "#4ac2c2", "#c2904a", "#4a4ac2", "#90c24a",
            "#c24a4a", "#4ac290", "#c2c24a", "#6fc24a", "#4a6fc2",
            "#c24ac2", "#904ac2", "#4ac24a", "#c2c24a", "#4ac290"
        ];
        
        uint256 colorIndex = (seed / (index + 1)) % 20;
        return (bgColors[colorIndex], strokes[colorIndex]);
    }

    function getObjectColor(uint256 seed, uint256 index, bool isMonochrome, bool isRainbow) internal pure returns (string memory, string memory) {
        if (isRainbow) {
            string[4] memory rainbowFills = ["#ff00ff", "#00ffff", "#ffff00", "#ff00aa"];
            string[4] memory rainbowStrokes = ["#aa00aa", "#00aaaa", "#aaaa00", "#aa0066"];
            return (rainbowFills[index % 4], rainbowStrokes[index % 4]);
        }
        
        if (isMonochrome) {
            uint256 gray = 150 + ((seed / (index + 1)) % 80);
            return (toGrayScale(gray), toGrayScale(gray - 40));
        }
        
        string[20] memory fills = [
            "#ffb347", "#7ed6a7", "#84c5ff", "#ff9aa2", "#c7ceea",
            "#ffdac1", "#b5ead7", "#ff9cee", "#fdfd96", "#e2f0cb",
            "#ffabab", "#ffc3a0", "#ff677d", "#d4a5a5", "#9eefe3",
            "#aec6cf", "#ffb3ba", "#bae1ff", "#ffffba", "#ffdfba"
        ];
        
        string[20] memory strokes = [
            "#cc7a00", "#3f8f63", "#457fb3", "#cc5c66", "#7a82b8",
            "#cc8a61", "#5a8a71", "#cc4a8e", "#cccc46", "#92b061",
            "#cc5555", "#cc6a40", "#cc2a3d", "#845555", "#4e8f83",
            "#5e767f", "#cc5a64", "#5a91cc", "#cccc5a", "#cc8f5a"
        ];
        
        uint256 colorIndex = (seed / (index + 1)) % 20;
        return (fills[colorIndex], strokes[colorIndex]);
    }

    function getCentralColors(uint256 seed, bool isMonochrome, bool isRainbow) internal pure returns (string memory, string memory) {
        if (isRainbow) {
            return ("#ff00ff", "#00ffff");
        }
        if (isMonochrome) {
            return ("#cccccc", "#666666");
        }
        
        string[10] memory outerColors = [
            "#9d7de2", "#e27d7d", "#7de29d", "#e2c27d", "#7da5e2",
            "#e27dc2", "#7de2e2", "#c2e27d", "#a57de2", "#e2e27d"
        ];
        
        string[10] memory innerColors = [
            "#5d3ea8", "#a83e3e", "#3ea85d", "#a8823e", "#3e65a8",
            "#a83e82", "#3ea8a8", "#82a83e", "#653ea8", "#a8a83e"
        ];
        
        uint256 index = seed % 10;
        return (outerColors[index], innerColors[index]);
    }

    function getAnimationValues(uint256 seed) internal pure returns (string memory) {
        int256 x1 = int256((seed % 40)) - 20;
        int256 y1 = int256(((seed / 100) % 40)) - 20;
        int256 x2 = int256(((seed / 200) % 30)) - 15;
        int256 y2 = int256(((seed / 300) % 50)) - 25;
        
        return string(abi.encodePacked(
            toString(x1), ' ', toString(y1), ';',
            toString(x2), ' ', toString(y2), ';0 0'
        ));
    }

    function toGrayScale(uint256 value) internal pure returns (string memory) {
        return string(abi.encodePacked('#', toHex(value), toHex(value), toHex(value)));
    }

    function toHex(uint256 value) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(2);
        result[0] = hexChars[value / 16];
        result[1] = hexChars[value % 16];
        return string(result);
    }

    function toString(int256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        bool negative = value < 0;
        uint256 absValue = uint256(negative ? -value : value);
        
        uint256 temp = absValue;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(negative ? digits + 1 : digits);
        uint256 index = buffer.length;
        
        while (absValue != 0) {
            index--;
            buffer[index] = bytes1(uint8(48 + absValue % 10));
            absValue /= 10;
        }
        
        if (negative) {
            buffer[0] = '-';
        }
        
        return string(buffer);
    }

    function generateAttributes(uint256 tokenId) internal pure returns (string memory) {
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId)));
        uint256 rarityRoll = seed % 1000;
        
        string memory rarity;
        string memory effect = "None";
        
        if (rarityRoll < 20) {
            rarity = "Legendary";
            effect = "Glowing";
        } else if (rarityRoll < 40) {
            rarity = "Epic";
            effect = "Rainbow";
        } else if (rarityRoll < 90) {
            rarity = "Rare";
            effect = "Monochrome";
        } else if (rarityRoll < 190) {
            rarity = "Uncommon";
            effect = "Pulsing";
        } else {
            rarity = "Common";
        }
        
        (string memory bgColor, ) = getCellColor(seed, 0, rarityRoll >= 20 && rarityRoll < 90, rarityRoll >= 20 && rarityRoll < 40);
        
        return string(abi.encodePacked(
            '{"trait_type":"Rarity","value":"', rarity, '"},',
            '{"trait_type":"Effect","value":"', effect, '"},',
            '{"trait_type":"Background","value":"', bgColor, '"},',
            '{"trait_type":"Elements","value":"', uint256(4).toString(), '"}'
        ));
    }
}

