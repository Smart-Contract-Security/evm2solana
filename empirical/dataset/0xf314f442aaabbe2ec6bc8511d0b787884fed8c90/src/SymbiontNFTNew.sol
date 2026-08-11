// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface ISymbiontRenderer {
    function generateSVG(uint256 tokenId, address owner, uint256 health, uint256 balanceAtMint, uint256 rarityTier) external view returns (string memory);
}

/**
 * @title SymbiontNFT
 * @notice Dynamic on-chain symbiotic creatures with rank-based rarity
 * 
 * Features:
 * - 1 NFT per wallet
 * - Rarity based on holder rank at mint (via Merkle proof)
 * - Health penalty on ALL token outflows (proportional)
 * - Feed with SYMB (2x per day, 100% to RewardDistributor)
 * - Dynamic SVG generation
 * - Reward eligibility: health > 50%
 */
contract SymbiontNFT is ERC721, Ownable {
    using Strings for uint256;
    
    IERC20 public immutable token;
    ISymbiontRenderer public renderer;
    address public treasury;
    address public rewardDistributor;
    
    struct Symbiont {
        uint256 health;              // 0-100
        uint256 balanceAtMint;       // SYMB balance snapshot at mint
        uint256 rarityTier;          // 0=Common, 1=Rare, 2=Epic, 3=Legendary
        uint256 birthTime;
        uint256 lastUpdateTime;
        uint256 lastFeedTime;
        uint256 feedCountToday;
    }
    
    mapping(uint256 => Symbiont) public symbionts;
    mapping(address => uint256) public walletToTokenId; // 1 NFT per wallet
    mapping(address => bool) public authorizedMinters; // hook, bonding curve, etc.
    
    uint256 public nextTokenId = 1;
    
    // Constants
    uint256 public constant INITIAL_HEALTH = 50;
    uint256 public constant MAX_HEALTH = 100;
    uint256 public constant FEED_HEALTH_BOOST = 5;
    uint256 public constant MAX_FEEDS_PER_DAY = 2;
    uint256 public constant MIN_HEALTH_FOR_REWARD = 50; // Must be > 50% to get rewards
    uint256 public feedCost = 1e18; // 1 SYMB (adjustable)
    
    event SymbiontMinted(address indexed owner, uint256 indexed tokenId, uint256 rarityTier, uint256 balanceAtMint);
    event SymbiontFed(uint256 indexed tokenId, uint256 newHealth, address feeder);
    event HealthUpdated(uint256 indexed tokenId, uint256 newHealth);
    event HealthPenalized(uint256 indexed tokenId, uint256 oldHealth, uint256 newHealth, uint256 balanceRatio);
    event FeedCostUpdated(uint256 newCost);
    
    constructor(address _token) ERC721("Symbiont", "SYMB-NFT") Ownable(msg.sender) {
        token = IERC20(_token);
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }
    
    function setRenderer(address _renderer) external onlyOwner {
        require(_renderer != address(0), "Invalid renderer");
        renderer = ISymbiontRenderer(_renderer);
    }
    
    function setRewardDistributor(address _rewardDistributor) external onlyOwner {
        require(_rewardDistributor != address(0), "Invalid address");
        rewardDistributor = _rewardDistributor;
    }
    
    function setFeedCost(uint256 newCost) external onlyOwner {
        feedCost = newCost;
        emit FeedCostUpdated(newCost);
    }
    
    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        require(minter != address(0), "Invalid address");
        authorizedMinters[minter] = authorized;
    }
    
    // ==================== HEALTH PENALTY (PROPORTIONAL) ====================
    
    /**
     * @notice Apply proportional health penalty when user's SYMB balance decreases
     * @dev Called by the SYMB token contract on EVERY transfer that reduces balance.
     * Works for: bonding curve sell, Uniswap sell, user-to-user transfer.
     * Formula: newHealth = health * (newBalance / oldBalance)
     * @param owner The wallet whose balance decreased
     * @param oldBal Balance before the transfer
     * @param newBal Balance after the transfer
     */
    function notifySell(address owner, uint256 oldBal, uint256 newBal) external {
        require(msg.sender == address(token), "Only token contract");
        
        uint256 tokenId = walletToTokenId[owner];
        if (tokenId == 0) return; // No NFT, skip
        
        Symbiont storage symbiont = symbionts[tokenId];
        if (symbiont.health == 0) return; // Already dead
        
        uint256 oldHealth = symbiont.health;
        
        // Proportional: newHealth = health * (newBal / oldBal)
        // Sell all → health = 0
        // Sell 50% → health drops by 50%
        // Sell 10% → health drops by 10%
        symbiont.health = oldHealth * newBal / oldBal;
        symbiont.lastUpdateTime = block.timestamp;
        
        emit HealthPenalized(tokenId, oldHealth, symbiont.health, (newBal * 100) / oldBal);
        emit HealthUpdated(tokenId, symbiont.health);
    }
    
    // ==================== AUTO MINT ====================
    
    /**
     * @notice Auto-mint NFT without Merkle proof (called by hook/bonding curve)
     * @dev No rarity tiers — all Symbionts are equal. Art varies by tokenId seed.
     */
    function autoMint(address to) external {
        require(authorizedMinters[msg.sender], "Unauthorized");
        require(walletToTokenId[to] == 0, "Already minted");
        
        uint256 balance = token.balanceOf(to);
        require(balance >= 1e16, "Need at least 0.01 SYMB");
        
        uint256 tokenId = nextTokenId++;
        
        symbionts[tokenId] = Symbiont({
            health: INITIAL_HEALTH,
            balanceAtMint: balance,
            rarityTier: 0, // No rarity — all equal
            birthTime: block.timestamp,
            lastUpdateTime: block.timestamp,
            lastFeedTime: 0,
            feedCountToday: 0
        });
        
        walletToTokenId[to] = tokenId;
        _safeMint(to, tokenId);
        
        emit SymbiontMinted(to, tokenId, 0, balance);
    }
    
    // ==================== FEEDING ====================
    
    /**
     * @notice Feed Symbiont with SYMB (2x per day max)
     */
    function feed(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(rewardDistributor != address(0), "RewardDistributor not set");
        
        Symbiont storage symbiont = symbionts[tokenId];
        
        // Reset counter if new day
        if (block.timestamp >= symbiont.lastFeedTime + 1 days) {
            symbiont.feedCountToday = 0;
        }
        
        require(symbiont.feedCountToday < MAX_FEEDS_PER_DAY, "Max 2 feeds per day");
        
        // Transfer SYMB to RewardDistributor (100%)
        // Token._update exempts this from health penalty (msg.sender == NFT contract)
        require(token.transferFrom(msg.sender, rewardDistributor, feedCost), "Transfer failed");
        
        // Boost health (no penalty from transfer, so simple add works)
        symbiont.health += FEED_HEALTH_BOOST;
        if (symbiont.health > MAX_HEALTH) symbiont.health = MAX_HEALTH;
        
        symbiont.lastFeedTime = block.timestamp;
        symbiont.feedCountToday++;
        
        emit SymbiontFed(tokenId, symbiont.health, msg.sender);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice Get current health of a Symbiont
     */
    function getHealth(uint256 tokenId) external view returns (uint256) {
        return symbionts[tokenId].health;
    }
    
    /**
     * @notice Check if wallet is eligible for reward (health > 50%)
     * @return eligible True if health > MIN_HEALTH_FOR_REWARD
     * @return health Current health value
     */
    function isEligible(address wallet) external view returns (bool eligible, uint256 health) {
        uint256 tokenId = walletToTokenId[wallet];
        if (tokenId == 0) return (false, 0);
        health = symbionts[tokenId].health;
        eligible = health > MIN_HEALTH_FOR_REWARD;
    }
    
    /**
     * @notice Generate SVG via external renderer
     */
    function generateSVG(uint256 tokenId) public view returns (string memory) {
        require(address(renderer) != address(0), "Renderer not set");
        Symbiont memory symbiont = symbionts[tokenId];
        return renderer.generateSVG(
            tokenId,
            ownerOf(tokenId),
            symbiont.health,
            symbiont.balanceAtMint,
            symbiont.rarityTier
        );
    }
    
    /**
     * @notice Token URI with on-chain metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        
        Symbiont memory symbiont = symbionts[tokenId];
        string memory svg = generateSVG(tokenId);
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name":"Symbiont #', tokenId.toString(), '",',
            '"description":"A living symbiotic creature from the bioluminescent depths",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            '"attributes":[',
            '{"trait_type":"Health","value":', symbiont.health.toString(), '}',
            ']}'
        ))));
        
        return string(abi.encodePacked('data:application/json;base64,', json));
    }
    
    /**
     * @notice Get Symbiont count for address
     */
    function getSymbiontCount(address wallet) external view returns (uint256) {
        return walletToTokenId[wallet] > 0 ? 1 : 0;
    }
    
    /**
     * @notice Get average health (for single NFT, just return health)
     */
    function getAverageHealth(address wallet) external view returns (uint256) {
        uint256 tokenId = walletToTokenId[wallet];
        if (tokenId == 0) return 0;
        return symbionts[tokenId].health;
    }
    
    /**
     * @notice Sync function (kept for compatibility, does nothing)
     */
    function syncSymbionts(address) external pure {
        // No-op: health updates happen via notifySell on every transfer
    }
    
    /**
     * @notice Apply decay (kept for hook compatibility, does nothing)
     * @dev Health penalty is now handled by token._update → notifySell
     */
    function applyDecay(address) external pure {
        // No-op: health penalty happens automatically via token._update
    }
    
    /**
     * @notice Update health based on time + balance ratio (lazy update)
     */
    function updateHealth(uint256 tokenId) public {
        Symbiont storage symbiont = symbionts[tokenId];
        address owner = ownerOf(tokenId);
        
        uint256 timeDelta = block.timestamp - symbiont.lastUpdateTime;
        if (timeDelta == 0) return;
        
        uint256 currentBalance = token.balanceOf(owner);
        if (symbiont.balanceAtMint == 0) return;
        
        uint256 ratio = (currentBalance * 100) / symbiont.balanceAtMint;
        
        // Health change based on balance ratio
        int256 healthChange = 0;
        
        if (ratio >= 100) {
            // Holding 100%+ → +1 health per day
            healthChange = int256(timeDelta / 1 days);
        } else if (ratio >= 75) {
            // 75-99% → stable
            healthChange = 0;
        } else if (ratio >= 50) {
            // 50-74% → -0.5 per day
            healthChange = -int256(timeDelta / 2 days);
        } else if (ratio >= 25) {
            // 25-49% → -1 per day
            healthChange = -int256(timeDelta / 1 days);
        } else {
            // <25% → -2 per day
            healthChange = -int256((timeDelta * 2) / 1 days);
        }
        
        // Apply health change
        if (healthChange > 0) {
            symbiont.health += uint256(healthChange);
            if (symbiont.health > MAX_HEALTH) symbiont.health = MAX_HEALTH;
        } else if (healthChange < 0) {
            uint256 decrease = uint256(-healthChange);
            if (symbiont.health > decrease) {
                symbiont.health -= decrease;
            } else {
                symbiont.health = 0;
            }
        }
        
        symbiont.lastUpdateTime = block.timestamp;
        emit HealthUpdated(tokenId, symbiont.health);
    }
}
