// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./WorldCupRewardToken.sol";

/**
 * @title WorldCupBall
 * @dev Fully onchain pixel-art football NFT that distributes daily utility ERC-20 tokens.
 * Compliant with EIP-2981 royalty standard for 1% fee support on OpenSea/Blur.
 */
contract WorldCupBall is ERC721, ERC2981, Ownable {
    using Strings for uint256;

    // Constants
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MAX_MINT_PER_WALLET = 5;
    uint256 public constant MAX_LIFETIME_REWARDS = 100000 * 10**18; // 100,000 WCB lifetime cap per NFT

    // State Variables
    address public immutable rewardToken;
    uint256 public nextTokenId = 1;
    uint256 public userMintCount;
    uint256 public deployerClaimableRewards = 70_000_000 * 10**18; // 7% of total supply claimable by deployer
    uint256 public burnedCount;
    uint256 public accumulatedForfeitedRewardsPerNFT;

    // Mappings
    mapping(uint256 => uint256) public lastClaimTime;
    mapping(address => uint256) public mintedPerWallet;
    mapping(uint256 => uint256) public totalClaimedRewards;
    mapping(uint256 => uint256) public forfeitedRewardsAtMint;

    // Nibble-encoded 16x16 Soccer Ball Grid (128 bytes)
    // 0 = Transparent, 1 = Ball Main Color, 2 = Black Line Color, 3 = Shadow Color
    bytes public constant SOCCER_BALL_GRID = hex"0000022222200000000221111112200000211122221112000211221111221120021211111111212021211122221112122121121111211212211221111112211221122111111221122121121111211212212111222211121202121111111121200211221111221120002111222211120000022111111220000000022222200000";

    struct Style {
        string name;
        string gradientStop1;
        string gradientStop2;
        string ballColor;
        string shadowColor;
        string ballClassName;
    }

    event RewardsClaimed(address indexed user, uint256 amount);
    event DeployerBonusMint(address indexed deployer, uint256 startId);
    event DeployerRewardsClaimed(address indexed deployer, uint256 amount);

    constructor() ERC721("WorldCupBall", "WCB") Ownable(msg.sender) {
        // Atomic deployment of the reward token
        rewardToken = address(new WorldCupRewardToken(msg.sender, address(this)));

        // Set default EIP-2981 royalty: 1% (100 basis points) paid to deployer
        _setDefaultRoyalty(msg.sender, 100);
    }

    /**
     * @notice Free minting of NFTs up to a maximum of 5 per wallet.
     * @param quantity The number of NFTs to mint.
     */
    function mint(uint256 quantity) external {
        require(quantity > 0, "Quantity must be > 0");
        require(mintedPerWallet[msg.sender] + quantity <= MAX_MINT_PER_WALLET, "Exceeds max mints per wallet");
        
        // Check supply including deployer bonus mints
        require(nextTokenId + quantity - 1 <= MAX_SUPPLY, "Exceeds max NFT supply");

        mintedPerWallet[msg.sender] += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = nextTokenId;
            _safeMint(msg.sender, tokenId);
            nextTokenId++;
            userMintCount++;

            // Every 50 user mints, deployer automatically receives 5 bonus mints
            if (userMintCount % 50 == 0) {
                address deployer = owner();
                uint256 startBonusId = nextTokenId;
                
                for (uint256 j = 0; j < 5; j++) {
                    if (nextTokenId <= MAX_SUPPLY) {
                        _safeMint(deployer, nextTokenId);
                        nextTokenId++;
                    }
                }
                emit DeployerBonusMint(deployer, startBonusId);
            }
        }
    }

    /**
     * @notice Returns the dynamically adjusted lifetime rewards cap for a given token ID.
     */
    function getLifetimeRewardsCap(uint256 tokenId) public view returns (uint256) {
        return MAX_LIFETIME_REWARDS + accumulatedForfeitedRewardsPerNFT - forfeitedRewardsAtMint[tokenId];
    }

    /**
     * @notice Claim rewards accumulated across multiple NFTs.
     * @param tokenIds List of NFT token IDs owned by the caller.
     */
    function claimRewards(uint256[] calldata tokenIds) external {
        uint256 totalReward = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "Not the owner");

            uint256 reward = getUnclaimedRewards(tokenId);
            if (reward > 0) {
                totalReward += reward;
                totalClaimedRewards[tokenId] += reward;

                uint256 cap = getLifetimeRewardsCap(tokenId);
                if (totalClaimedRewards[tokenId] == cap) {
                    lastClaimTime[tokenId] = block.timestamp;
                } else {
                    uint256 timeElapsed = block.timestamp - lastClaimTime[tokenId];
                    uint256 hoursElapsed = timeElapsed / 1 hours;
                    lastClaimTime[tokenId] += hoursElapsed * 1 hours;
                }
            }
        }

        require(totalReward > 0, "No rewards accrued");
        IERC20(rewardToken).transfer(msg.sender, totalReward);
        emit RewardsClaimed(msg.sender, totalReward);
    }

    /**
     * @notice Allows the deployer (owner) to claim their reserved 7% reward tokens.
     * @param amount The amount of tokens to claim.
     */
    function claimDeployerRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(amount <= deployerClaimableRewards, "Exceeds deployer claimable rewards");

        deployerClaimableRewards -= amount;
        IERC20(rewardToken).transfer(owner(), amount);
        emit DeployerRewardsClaimed(owner(), amount);
    }

    /**
     * @notice Burns the NFT and claims a payout equal to 10% of the remaining lifetime reward pool.
     * The remaining 90% is redistributed pro-rata to other active NFTs.
     * @param tokenId The NFT token ID to burn.
     */
    function burn(uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(_isAuthorized(tokenOwner, msg.sender, tokenId), "Not authorized to burn");

        uint256 activeNFTsBefore = nextTokenId - 1 - burnedCount;
        require(activeNFTsBefore > 0, "No active NFTs");

        uint256 currentLifetimeCap = getLifetimeRewardsCap(tokenId);
        uint256 remaining = currentLifetimeCap - totalClaimedRewards[tokenId];
        uint256 burnReward = (remaining * 10) / 100;
        uint256 forfeitedAmount = remaining - burnReward;

        if (burnReward > 0) {
            IERC20(rewardToken).transfer(tokenOwner, burnReward);
        }

        _burn(tokenId);
        burnedCount++;

        // Distribute forfeited amount to remaining active NFTs
        uint256 activeNFTsAfter = activeNFTsBefore - 1;
        if (activeNFTsAfter > 0) {
            accumulatedForfeitedRewardsPerNFT += forfeitedAmount / activeNFTsAfter;
        }
    }

    /**
     * @notice Calculate accumulated unclaimed rewards for a single NFT.
     */
    /**
     * @notice Get hourly reward rate for a given token ID based on its style attributes.
     */
    function getHourlyRewardRate(uint256 tokenId) public pure returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId)));
        uint256 rand = seed % 100;
        if (rand == 0) { // 1% chance (Super Rare / Legendary)
            return 1000 * 10**18;
        } else if (rand <= 4) { // 4% chance (Epic)
            return 500 * 10**18;
        } else if (rand <= 14) { // 10% chance (Rare)
            return 250 * 10**18;
        } else if (rand <= 34) { // 20% chance (Uncommon)
            return 100 * 10**18;
        } else if (rand <= 64) { // 30% chance (Common)
            return 50 * 10**18;
        } else { // 35% chance (Basic)
            return 10 * 10**18;
        }
    }

    function getUnclaimedRewards(uint256 tokenId) public view returns (uint256) {
        if (_ownerOf(tokenId) == address(0)) return 0;

        uint256 remaining = getLifetimeRewardsCap(tokenId) - totalClaimedRewards[tokenId];
        if (remaining == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastClaimTime[tokenId];
        uint256 hoursElapsed = timeElapsed / 1 hours;
        uint256 accrued = hoursElapsed * getHourlyRewardRate(tokenId);

        return accrued > remaining ? remaining : accrued;
    }

    /**
     * @notice Utility view for frontends to batch-query total unclaimed rewards for multiple NFTs.
     */
    function getUnclaimedRewardsBatch(uint256[] calldata tokenIds) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            total += getUnclaimedRewards(tokenIds[i]);
        }
        return total;
    }

    /**
     * @notice Get dynamic aesthetic style based on token ID seed.
     */
    function getStyle(uint256 tokenId) public pure returns (Style memory) {
        string[10] memory stop1s = [
            "#8A2387", // Cyber Purple
            "#F12711", // Electric Orange
            "#11998E", // Neo Emerald
            "#00C6FF", // Cyber Teal
            "#4E54C8", // Royal Indigo
            "#232526", // Dark Obsidian
            "#F3904F", // Sunset Gold
            "#020024", // Cosmic Navy
            "#1D976C", // Radioactive Green
            "#141E30"  // Cyber Charcoal
        ];
        string[10] memory stop2s = [
            "#E94057", // Neon Pink
            "#F5AF19", // Vaporwave Yellow
            "#38EF7D", // Acid Lime
            "#0072FF", // Deep Velvet Blue
            "#8F94FB", // Pastel Orchid
            "#414345", // Iron Grey
            "#3B4371", // Twilight Lavender
            "#00D4FF", // Electric Blue
            "#93F9B9", // Soft Mint
            "#243B55"  // Metallic Steel
        ];
        string[10] memory styleNames = [
            "Cyber Purple & Neon Pink",
            "Electric Orange & Vaporwave Yellow",
            "Neo Emerald & Acid Lime",
            "Cyber Teal & Deep Velvet Blue",
            "Royal Indigo & Pastel Orchid",
            "Dark Obsidian & Iron Grey",
            "Sunset Gold & Twilight Lavender",
            "Cosmic Navy & Electric Blue",
            "Radioactive Green & Soft Mint",
            "Cyber Charcoal & Metallic Steel"
        ];

        string[6] memory ballColors = [
            "#FFFFFF", // Classic White
            "#FFD700", // Golden Trophy
            "#E3E3E3", // Polished Silver
            "#39FF14", // Cyber Neon Green
            "#FF2A6D", // Synthwave Magenta
            "#00F3FF"  // Tron Cyan
        ];
        string[6] memory shadowColors = [
            "#D0D0D0",
            "#B59400",
            "#A8A8A8",
            "#28C70D",
            "#B30E40",
            "#00B5BD"
        ];
        string[6] memory ballClassNames = [
            "Classic White",
            "Golden Trophy",
            "Polished Silver",
            "Cyber Neon Green",
            "Synthwave Magenta",
            "Tron Cyan"
        ];

        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId)));
        uint256 gradIndex = seed % 10;
        uint256 rand = seed % 100;
        uint256 ballIndex;
        if (rand == 0) {
            ballIndex = 1; // Golden Trophy
        } else if (rand <= 4) {
            ballIndex = 5; // Tron Cyan
        } else if (rand <= 14) {
            ballIndex = 4; // Synthwave Magenta
        } else if (rand <= 34) {
            ballIndex = 3; // Cyber Neon Green
        } else if (rand <= 64) {
            ballIndex = 2; // Polished Silver
        } else {
            ballIndex = 0; // Classic White
        }

        return Style(
            styleNames[gradIndex],
            stop1s[gradIndex],
            stop2s[gradIndex],
            ballColors[ballIndex],
            shadowColors[ballIndex],
            ballClassNames[ballIndex]
        );
    }

    /**
     * @dev Overrides ERC-2981 and ERC-721 supportsInterface function.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Overrides ERC721 update hook to handle claim resetting.
     * Rewards are reset upon transfer (or burn), NOT transferred to the previous owner.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address previousOwner = super._update(to, tokenId, auth);

        // Mints, transfers, and burns all reset the last claim time to now
        lastClaimTime[tokenId] = block.timestamp;

        // On mint, initialize the snapshot of forfeited rewards
        if (previousOwner == address(0)) {
            forfeitedRewardsAtMint[tokenId] = accumulatedForfeitedRewardsPerNFT;
        }

        return previousOwner;
    }

    /**
     * @dev Renders highly optimized horizontal pixel spans from the SOCCER_BALL_GRID lookup table.
     * Shifts ball coordinate (+4, +4) to center 16x16 pixel art inside 24x24 canvas.
     */
    function _drawFootball(string memory ballColor, string memory shadowColor) internal pure returns (string memory) {
        bytes memory grid = SOCCER_BALL_GRID;
        bytes memory buffer;

        for (uint256 y = 0; y < 16; y++) {
            uint8 currentColorIndex = 0;
            uint256 startX = 0;
            for (uint256 x = 0; x < 16; x++) {
                uint256 i = y * 16 + x;
                uint256 byteIndex = i / 2;
                uint8 byteValue = uint8(grid[byteIndex]);
                uint8 colorIndex = (i % 2 == 0) ? (byteValue >> 4) : (byteValue & 0x0F);

                if (colorIndex != currentColorIndex) {
                    if (currentColorIndex != 0) {
                        uint256 width = x - startX;
                        string memory color = (currentColorIndex == 1) ? ballColor : 
                                              ((currentColorIndex == 2) ? "#111111" : shadowColor);
                        buffer = abi.encodePacked(
                            buffer,
                            '<rect x="', (startX + 4).toString(),
                            '" y="', (y + 4).toString(),
                            '" width="', width.toString(),
                            '" height="1" fill="', color, '"/>'
                        );
                    }
                    currentColorIndex = colorIndex;
                    startX = x;
                }
            }
            if (currentColorIndex != 0) {
                uint256 width = 16 - startX;
                string memory color = (currentColorIndex == 1) ? ballColor : 
                                      ((currentColorIndex == 2) ? "#111111" : shadowColor);
                buffer = abi.encodePacked(
                    buffer,
                    '<rect x="', (startX + 4).toString(),
                    '" y="', (y + 4).toString(),
                    '" width="', width.toString(),
                    '" height="1" fill="', color, '"/>'
                );
            }
        }
        return string(buffer);
    }

    /**
     * @notice Generates a base64 encoded metadata standard for the given token ID.
     * Complies with the OpenSea NFT Metadata Standard.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        Style memory style = getStyle(tokenId);
        string memory footballRects = _drawFootball(style.ballColor, style.shadowColor);
        uint256 hourlyRate = getHourlyRewardRate(tokenId) / 10**18;

        // Build premium animated SVG
        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100%" height="100%" shape-rendering="crispEdges">',
            '<style>',
            '@keyframes float {',
            '0% { transform: translateY(0px); }',
            '50% { transform: translateY(-0.8px); }',
            '100% { transform: translateY(0px); }',
            '}',
            '@keyframes pulse {',
            '0% { transform: scale(1); opacity: 0.25; }',
            '50% { transform: scale(0.85); opacity: 0.15; }',
            '100% { transform: scale(1); opacity: 0.25; }',
            '}',
            '.ball { animation: float 4s ease-in-out infinite; transform-origin: 12px 12px; }',
            '.shadow { animation: pulse 4s ease-in-out infinite; transform-origin: 12px 20.5px; }',
            '</style>',
            '<defs>',
            '<linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" stop-color="', style.gradientStop1, '"/>',
            '<stop offset="100%" stop-color="', style.gradientStop2, '"/>',
            '</linearGradient>',
            '</defs>',
            '<rect width="24" height="24" rx="2" fill="url(#bgGrad)"/>',
            '<rect x="1" y="1" width="22" height="22" rx="1.5" fill="none" stroke="#FFFFFF" stroke-width="0.3" stroke-opacity="0.3"/>',
            '<circle cx="12" cy="12" r="6" fill="none" stroke="#FFFFFF" stroke-width="0.15" stroke-opacity="0.15"/>',
            '<ellipse class="shadow" cx="12" cy="20.5" rx="4" ry="0.6" fill="#000000"/>',
            '<g class="ball">',
            footballRects,
            '</g>',
            '<text x="2" y="2.5" font-family="system-ui, -apple-system, sans-serif" font-size="0.75" font-weight="bold" fill="#FFFFFF" opacity="0.8">', hourlyRate.toString(), ' WCB/Hour</text>',
            '<text x="12" y="22.3" font-family="system-ui, -apple-system, sans-serif" font-size="0.8" font-weight="bold" fill="#FFFFFF" text-anchor="middle" letter-spacing="0.1" opacity="0.8">World Cup Ball 2026</text>',
            '</svg>'
        ));

        string memory svgBase64 = Base64.encode(bytes(svg));

        // Build JSON Metadata compliant with standard OpenSea metadata structure
        string memory json = string(abi.encodePacked(
            '{"name": "WorldCupBall #', tokenId.toString(), '",',
            '"description": "A fully onchain 16x16 pixelated football trading card. Every card is pseudo-randomly styled, generated, and fully stored on the blockchain, accumulating dynamic WCB utility reward tokens daily based on its attributes.",',
            '"image": "data:image/svg+xml;base64,', svgBase64, '",',
            '"attributes": [',
            '{"trait_type": "Background Theme", "value": "', style.name, '"},',
            '{"trait_type": "Ball Class", "value": "', style.ballClassName, '"},',
            '{"trait_type": "Hourly Reward Rate", "value": "', hourlyRate.toString(), ' WCB/Hour"},',
            '{"trait_type": "Daily Reward Rate", "value": "', (hourlyRate * 24).toString(), ' WCB"},',
            '{"trait_type": "Max Lifetime Reward", "value": "', (getLifetimeRewardsCap(tokenId) / 10**18).toString(), ' WCB"},',
            '{"trait_type": "OnChain Source", "value": "Solidity Decoder"}',
            ']}'
        ));

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
