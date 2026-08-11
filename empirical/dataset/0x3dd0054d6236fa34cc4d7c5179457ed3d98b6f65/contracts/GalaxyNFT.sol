// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SVGRenderer.sol";

/// @title Galaxy Seeds
/// @notice Fully on-chain generative NFT - galaxy commons + crystal seed NFTs
/// @dev Art, metadata, and mechanics entirely on-chain. No IPFS.
contract GalaxyNFT is ERC721, ERC721Burnable, Ownable, ReentrancyGuard {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 public constant MAX_COMMON_SUPPLY = 10_000;
    uint256 public constant MAX_PER_WALLET    = 10;
    uint256 public constant MUTATION_RATE     = 10; // 10%
    uint256 public constant MINT_PRICE        = 0.0001 ether;

    // Token ID ranges
    // Commons:  1 – 10,000
    // Seeds:    10,001 – 12,000 (max 2,000 seeds)
    uint256 private constant SEED_ID_START    = 10_001;
    uint256 private constant MAX_SEED_SUPPLY  = 2_000;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    SVGRenderer public renderer;

    uint256 public commonsMinted;
    uint256 public seedsMinted;
    bool    public mintOpen;

    // Per-token data
    mapping(uint256 => bool)    public isMutated;       // common: is core mutated?
    mapping(uint256 => uint8)   public colorIndex;      // common: core colour 0-5
    mapping(uint256 => uint256) public mintedAt;        // common: timestamp of mint
    mapping(uint256 => bool)    public isSeed;          // is this token a seed?
    mapping(uint256 => bool)    public isMutatedSeed;   // seed: is it a mutated seed?
    mapping(uint256 => bytes32) public seedDNA;         // seed: hash of burned token IDs

    // Wallet limits
    mapping(address => uint256) public commonsMintedByWallet;

    // PFP contract - set later
    address public pfpContract;

    // Treasury wallet — receives mint funds directly
    address public treasuryWallet;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event CommonMinted(address indexed to, uint256 tokenId, bool mutated, uint8 color);
    event SeedForged(address indexed by, uint256 seedId, bool mutated, bytes32 dna);
    event PFPContractSet(address pfpContract);
    event TreasuryWalletUpdated(address newWallet);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    constructor(address rendererAddress, address _treasuryWallet) ERC721("Galaxy Seeds", "GLXY") Ownable(msg.sender) {
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        renderer = SVGRenderer(rendererAddress);
        treasuryWallet = _treasuryWallet;
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    /// @notice Mint common NFTs. Each costs mintPrice ETH. Max 10 per wallet.
    /// @param quantity Number to mint (1-10 per tx, wallet max 10 total)
    function mint(uint256 quantity) external payable nonReentrant {
        require(mintOpen, "Mint not open");
        require(quantity > 0 && quantity <= MAX_PER_WALLET, "Invalid quantity");
        require(commonsMintedByWallet[msg.sender] + quantity <= MAX_PER_WALLET, "Wallet limit reached");
        require(commonsMinted + quantity <= MAX_COMMON_SUPPLY, "Supply exhausted");

        uint256 totalCost = MINT_PRICE * quantity;
        require(msg.value >= totalCost, "Insufficient ETH");

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = ++commonsMinted;
            _mintCommon(msg.sender, tokenId, i);
        }

        commonsMintedByWallet[msg.sender] += quantity;

        // Send mint funds directly to treasury wallet
        payable(treasuryWallet).transfer(totalCost);

        // Refund excess
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
    }

    function _mintCommon(address to, uint256 tokenId, uint256 saltIndex) internal {
        // Deterministic randomness from block data + sender + token
        uint256 rand = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            msg.sender,
            tokenId,
            saltIndex
        )));

        bool mutated = (rand % 100) < MUTATION_RATE;
        uint8 color  = uint8((rand >> 8) % 6);

        isMutated[tokenId]  = mutated;
        colorIndex[tokenId] = color;
        mintedAt[tokenId]   = block.timestamp;

        _safeMint(to, tokenId);
        emit CommonMinted(to, tokenId, mutated, color);
    }

    // -------------------------------------------------------------------------
    // Forge — Burn 5 → Seed
    // -------------------------------------------------------------------------

    /// @notice Burn exactly 5 common NFTs to forge 1 seed.
    ///         If any burned token has a mutated core → seed is mutated.
    /// @param tokenIds Array of exactly 5 common token IDs you own
    function forgeFromFive(uint256[5] calldata tokenIds) external nonReentrant {
        require(seedsMinted < MAX_SEED_SUPPLY, "Seed supply exhausted");
        bool mutatedFound = false;

        for (uint256 i = 0; i < 5; i++) {
            _validateAndBurn(tokenIds[i]);
            if (isMutated[tokenIds[i]]) mutatedFound = true;
        }

        bytes32 dna = keccak256(abi.encodePacked(
            tokenIds[0], tokenIds[1], tokenIds[2], tokenIds[3], tokenIds[4]
        ));

        _forgeSeed(msg.sender, mutatedFound, dna);
    }

    /// @notice Burn exactly 10 common NFTs to forge 1 GUARANTEED mutated seed.
    ///         None need to be mutated — burning 10 guarantees mutation.
    /// @param tokenIds Array of exactly 10 common token IDs you own
    function forgeFromTen(uint256[10] calldata tokenIds) external nonReentrant {
        require(seedsMinted < MAX_SEED_SUPPLY, "Seed supply exhausted");

        for (uint256 i = 0; i < 10; i++) {
            _validateAndBurn(tokenIds[i]);
        }

        bytes32 dna = keccak256(abi.encodePacked(
            tokenIds[0], tokenIds[1], tokenIds[2], tokenIds[3], tokenIds[4],
            tokenIds[5], tokenIds[6], tokenIds[7], tokenIds[8], tokenIds[9]
        ));

        // Always mutated when burning 10
        _forgeSeed(msg.sender, true, dna);
    }

    function _validateAndBurn(uint256 tokenId) internal {
        require(ownerOf(tokenId) == msg.sender, "Not your token");
        require(!isSeed[tokenId], "Cannot burn a seed");
        require(tokenId >= 1 && tokenId <= MAX_COMMON_SUPPLY, "Invalid token");
        _burn(tokenId);
    }

    /// @notice Override ERC721Burnable.burn() to protect seeds from direct burning.
    ///         Seeds can only be destroyed via the future PFP claim mechanic, not burned freely.
    function burn(uint256 tokenId) public override {
        require(!isSeed[tokenId], "Seeds cannot be burned directly");
        super.burn(tokenId);
    }

    function _forgeSeed(address to, bool mutated, bytes32 dna) internal {
        uint256 seedId = SEED_ID_START + seedsMinted;
        seedsMinted++;

        isSeed[seedId]        = true;
        isMutatedSeed[seedId] = mutated;
        seedDNA[seedId]       = dna;
        mintedAt[seedId]      = block.timestamp;

        _safeMint(to, seedId);
        emit SeedForged(to, seedId, mutated, dna);
    }

    // -------------------------------------------------------------------------
    // TokenURI — fully on-chain
    // -------------------------------------------------------------------------
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        SVGRenderer.TokenData memory data = SVGRenderer.TokenData({
            tokenId:      tokenId,
            isMutated:    isMutated[tokenId],
            colorIndex:   colorIndex[tokenId],
            mintedAt:     mintedAt[tokenId],
            isSeed:       isSeed[tokenId],
            isMutatedSeed: isMutatedSeed[tokenId]
        });

        if (isSeed[tokenId]) {
            return renderer.renderSeed(data);
        } else {
            return renderer.renderCommon(data);
        }
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------
    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
    }


    function setPFPContract(address _pfp) external onlyOwner {
        pfpContract = _pfp;
        emit PFPContractSet(_pfp);
    }

    /// @notice Emergency withdraw — sends any stuck ETH to treasury wallet
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "Nothing to withdraw");
        payable(treasuryWallet).transfer(bal);
    }

    /// @notice Update the treasury wallet address
    function setTreasuryWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid wallet");
        treasuryWallet = _wallet;
        emit TreasuryWalletUpdated(_wallet);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Days since a token was minted
    function tokenAge(uint256 tokenId) external view returns (uint256) {
        require(mintedAt[tokenId] > 0, "Not minted");
        return (block.timestamp - mintedAt[tokenId]) / 1 days;
    }

    /// @notice Dots remaining on a common NFT
    function dotsRemaining(uint256 tokenId) external view returns (uint256) {
        require(!isSeed[tokenId], "Seeds have no dots");
        uint256 daysPassed = (block.timestamp - mintedAt[tokenId]) / 1 days;
        if (daysPassed >= 45) return 0;
        return 45 - daysPassed;
    }

    /// @notice How many commons a wallet can still mint
    function mintsRemaining(address wallet) external view returns (uint256) {
        return MAX_PER_WALLET - commonsMintedByWallet[wallet];
    }

    /// @notice Total commons remaining in supply
    function commonsRemaining() external view returns (uint256) {
        return MAX_COMMON_SUPPLY - commonsMinted;
    }

    /// @notice Total seeds remaining
    function seedsRemaining() external view returns (uint256) {
        return MAX_SEED_SUPPLY - seedsMinted;
    }
}
