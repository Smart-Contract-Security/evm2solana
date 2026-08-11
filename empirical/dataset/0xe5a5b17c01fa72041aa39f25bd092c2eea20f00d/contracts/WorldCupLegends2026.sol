// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract WorldCupLegends2026 is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable, ReentrancyGuard {
    // ========== CONSTANTS ==========
    uint256 public constant MAX_SUPPLY = 3200;
    uint256 public constant PAID_PRICE = 0.00015 ether;
    uint256 public constant MAX_MINT_PER_TX = 5;
    uint256 public constant MAX_MINT_PER_WALLET = 5;
    
    // ========== TIER SYSTEM ==========
    enum Tier { LEGENDARY, EPIC, RARE, UNCOMMON, COMMON }
    
    // ========== STATE ==========
    mapping(uint256 => uint256) public tokenCountry; // tokenId => countryIndex
    mapping(uint256 => Tier) public tokenTier;        // tokenId => tier
    mapping(Tier => uint256) public tierMinted;
    mapping(Tier => uint256) public tierMaxSupply;
    
    mapping(uint256 => string) private _tokenURIs;    // tokenId => IPFS URI
    
    string private _baseURIoverride;
    
    uint256 public totalMinted;
    bool public paused = false;
    
    mapping(address => uint256) public addressMinted;
    
    // Whitelist
    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public whitelistMinted;
    uint256 public whitelistMaxMint = 2;
    
    // Randomness seed
    uint256 private _seed;
    
    // ========== EVENTS ==========
    event Minted(address indexed minter, uint256 tokenId, string country, Tier tier);
    event Paused(bool status);
    
    // ========== COUNTRIES DATA ==========
    string[] public countries = [
        "Brazil", "Argentina", "France", "Germany",
        "Spain", "England", "Italy", "Portugal", "Netherlands", "Japan",
        "Croatia", "Morocco", "Senegal", "Colombia", "Uruguay", "Mexico", "USA", "South Korea",
        "Cameroon", "Ghana", "Poland", "Switzerland", "Denmark", "Serbia", "Australia", "Saudi Arabia",
        "Ecuador", "Tunisia", "Canada", "Wales", "Iran", "Costa Rica"
    ];
    
    Tier[] public countryTiers = [
        Tier.LEGENDARY, Tier.LEGENDARY, Tier.LEGENDARY, Tier.LEGENDARY,
        Tier.EPIC, Tier.EPIC, Tier.EPIC, Tier.EPIC, Tier.EPIC, Tier.EPIC,
        Tier.RARE, Tier.RARE, Tier.RARE, Tier.RARE, Tier.RARE, Tier.RARE, Tier.RARE, Tier.RARE,
        Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON, Tier.UNCOMMON,
        Tier.COMMON, Tier.COMMON, Tier.COMMON, Tier.COMMON, Tier.COMMON, Tier.COMMON
    ];
    
    // Gacha weights (out of 10000)
    uint256 public constant WEIGHT_LEGENDARY = 500;   // 5%
    uint256 public constant WEIGHT_EPIC = 1000;        // 10%
    uint256 public constant WEIGHT_RARE = 2000;        // 20%
    uint256 public constant WEIGHT_UNCOMMON = 3000;    // 30%
    uint256 public constant WEIGHT_COMMON = 3500;      // 35%
    
    // ========== CONSTRUCTOR ==========
    constructor() ERC721("World Cup Legends 2026", "WCL2026") Ownable(msg.sender) {
        tierMaxSupply[Tier.LEGENDARY] = 400;
        tierMaxSupply[Tier.EPIC] = 600;
        tierMaxSupply[Tier.RARE] = 800;
        tierMaxSupply[Tier.UNCOMMON] = 800;
        tierMaxSupply[Tier.COMMON] = 600;
        
        _seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
    }
    
    // ========== GACHA MINT ==========
    function mint(uint256 quantity) external payable nonReentrant {
        require(!paused, "Minting is paused");
        require(quantity > 0 && quantity <= MAX_MINT_PER_TX, "Invalid quantity");
        require(totalMinted + quantity <= MAX_SUPPLY, "Max supply reached");
        require(addressMinted[msg.sender] + quantity <= MAX_MINT_PER_WALLET, "Wallet limit exceeded");
        
        uint256 requiredPayment = quantity * PAID_PRICE;
        require(msg.value >= requiredPayment, "Insufficient payment");
        
        addressMinted[msg.sender] += quantity;
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 randomVal = _pseudoRandom();
            
            // Roll gacha for tier
            Tier tier_ = _rollTier(randomVal);
            
            // Pick random country within that tier
            uint256 countryIndex = _pickCountry(tier_, randomVal >> 128);
            
            // Store token data
            totalMinted++;
            uint256 tokenId = totalMinted;
            tokenCountry[tokenId] = countryIndex;
            tokenTier[tokenId] = tier_;
            tierMinted[tier_]++;
            
            // Set metadata URI
            _tokenURIs[tokenId] = _getMetadataURI(countryIndex);
            
            _safeMint(msg.sender, tokenId);
            
            emit Minted(msg.sender, tokenId, countries[countryIndex], tier_);
        }
    }
    
    function whitelistMint(uint256 quantity) external payable nonReentrant {
        require(!paused, "Minting is paused");
        require(isWhitelisted[msg.sender], "Not whitelisted");
        require(quantity > 0 && quantity <= whitelistMaxMint, "Invalid quantity");
        require(whitelistMinted[msg.sender] + quantity <= whitelistMaxMint, "Whitelist limit exceeded");
        require(totalMinted + quantity <= MAX_SUPPLY, "Max supply reached");
        
        whitelistMinted[msg.sender] += quantity;
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 randomVal = _pseudoRandom();
            Tier tier_ = _rollTier(randomVal);
            uint256 countryIndex = _pickCountry(tier_, randomVal >> 128);
            
            totalMinted++;
            uint256 tokenId = totalMinted;
            tokenCountry[tokenId] = countryIndex;
            tokenTier[tokenId] = tier_;
            tierMinted[tier_]++;
            
            _tokenURIs[tokenId] = _getMetadataURI(countryIndex);
            
            _safeMint(msg.sender, tokenId);
            
            emit Minted(msg.sender, tokenId, countries[countryIndex], tier_);
        }
    }
    
    // ========== INTERNAL GACHA LOGIC ==========
    function _rollTier(uint256 randomVal) internal pure returns (Tier) {
        uint256 roll = randomVal % 10000;
        
        if (roll < WEIGHT_LEGENDARY) return Tier.LEGENDARY;
        if (roll < WEIGHT_LEGENDARY + WEIGHT_EPIC) return Tier.EPIC;
        if (roll < WEIGHT_LEGENDARY + WEIGHT_EPIC + WEIGHT_RARE) return Tier.RARE;
        if (roll < WEIGHT_LEGENDARY + WEIGHT_EPIC + WEIGHT_RARE + WEIGHT_UNCOMMON) return Tier.UNCOMMON;
        return Tier.COMMON;
    }
    
    function _pickCountry(Tier tier_, uint256 randomVal) internal pure returns (uint256) {
        uint256 start;
        uint256 end;
        
        if (tier_ == Tier.LEGENDARY) { start = 0; end = 3; }
        else if (tier_ == Tier.EPIC) { start = 4; end = 9; }
        else if (tier_ == Tier.RARE) { start = 10; end = 17; }
        else if (tier_ == Tier.UNCOMMON) { start = 18; end = 25; }
        else { start = 26; end = 31; }
        
        uint256 range = end - start + 1;
        uint256 offset = randomVal % range;
        return start + offset;
    }
    
    function _pseudoRandom() private returns (uint256) {
        _seed = uint256(keccak256(abi.encodePacked(
            _seed,
            block.timestamp,
            block.prevrandao,
            totalMinted,
            msg.sender
        )));
        return _seed;
    }
    
    function _getMetadataURI(uint256 countryIndex) internal view returns (string memory) {
        if (bytes(_baseURIoverride).length > 0) {
            uint256 metaId = countryIndex + 1;
            return string(abi.encodePacked(_baseURIoverride, Strings.toString(metaId), ".json"));
        }
        return string(abi.encodePacked("ipfs://PLACEHOLDER/", Strings.toString(countryIndex + 1), ".json"));
    }
    
    // ========== ADMIN FUNCTIONS ==========
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }
    
    // Update BaseURI override
    function setBaseURI(string calldata uri) external onlyOwner {
        _baseURIoverride = uri;
    }
    
    function addToWhitelist(address[] memory addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            isWhitelisted[addresses[i]] = true;
        }
    }
    
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
    
    // ========== VIEW FUNCTIONS ==========
    function getCountryInfo(uint256 countryIndex) external view returns (
        string memory name,
        Tier tier,
        uint256 tierMintedCount,
        uint256 tierMaxSupplyCount
    ) {
        require(countryIndex < 32, "Invalid country index");
        Tier tier_ = countryTiers[countryIndex];
        return (
            countries[countryIndex],
            tier_,
            tierMinted[tier_],
            tierMaxSupply[tier_]
        );
    }
    
    function getTierInfo(Tier tier_) external view returns (uint256 minted_, uint256 maxSupply_) {
        return (tierMinted[tier_], tierMaxSupply[tier_]);
    }
    
    function getMintPrice(uint256 quantity) external view returns (uint256 price, uint256 freeCount, uint256 paidCount) {
        return (quantity * PAID_PRICE, 0, quantity);
    }
    
    function getTokenInfo(uint256 tokenId) external view returns (
        string memory country,
        Tier tier,
        string memory uri
    ) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return (
            countries[tokenCountry[tokenId]],
            tokenTier[tokenId],
            _tokenURIs[tokenId]
        );
    }
    
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage, ERC721) returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        string memory uri = _tokenURIs[tokenId];
        if (bytes(uri).length > 0) {
            return uri;
        }
        
        return "";
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }
}
