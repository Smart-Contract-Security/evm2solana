// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PearlSVGRenderer.sol";

/// @title Pearl Block Heroes — On-chain NFT collection celebrating Pearl chain blocks
/// @notice Each NFT represents one of the first 8,888 Pearl blocks. tokenId = block number.
/// @dev Pure on-chain SVG, no IPFS. Paid in WPRL (Wrapped Pearl).
contract PearlBlockHeroes is ERC721, Ownable, ReentrancyGuard {

    // ---------- Constants ----------

    /// @notice WPRL token (Wrapped Pearl on Ethereum mainnet)
    IERC20 public constant WPRL = IERC20(0x07696DcaB55E62cfef953666b29Fe1970518cB00);

    /// @notice Total max NFTs (first 8,888 Pearl blocks)
    uint256 public constant MAX_SUPPLY = 8888;

    /// @notice Max mints per wallet (whale protection)
    uint256 public constant MAX_PER_WALLET = 20;

    // ---------- State ----------

    /// @notice Mint price in WPRL (18 decimals). Default 0.5 WPRL.
    uint256 public mintPrice = 0.5 ether;

    /// @notice Treasury address (where mint fees go)
    address public treasury;

    /// @notice Mint enabled flag
    bool public mintActive;

    /// @notice Total minted so far
    uint256 public totalMinted;

    /// @notice Mint count per wallet
    mapping(address => uint256) public mintCount;

    // ---------- Events ----------

    event BlockMinted(address indexed minter, uint256 indexed blockNumber);
    event MintActiveChanged(bool active);
    event PriceChanged(uint256 newPrice);
    event TreasuryChanged(address newTreasury);

    // ---------- Constructor ----------

    constructor(address _treasury)
        ERC721("Pearl Block Heroes", "PBH")
        Ownable(msg.sender)
    {
        require(_treasury != address(0), "Zero treasury");
        treasury = _treasury;
    }

    // ---------- Mint ----------

    /// @notice Mint one or more specific block-number NFTs
    /// @param blockNumbers Array of block numbers to claim (1..MAX_SUPPLY)
    function mintBlocks(uint256[] calldata blockNumbers) external nonReentrant {
        require(mintActive, "Mint not active");
        uint256 qty = blockNumbers.length;
        require(qty > 0 && qty <= 20, "Invalid quantity");
        require(mintCount[msg.sender] + qty <= MAX_PER_WALLET, "Wallet limit");
        require(totalMinted + qty <= MAX_SUPPLY, "Would exceed max supply");

        uint256 totalCost = mintPrice * qty;
        require(
            WPRL.transferFrom(msg.sender, treasury, totalCost),
            "WPRL transfer failed"
        );

        mintCount[msg.sender] += qty;
        totalMinted += qty;

        for (uint256 i = 0; i < qty; i++) {
            uint256 blockNum = blockNumbers[i];
            require(blockNum >= 1 && blockNum <= MAX_SUPPLY, "Block out of range");
            // tokenId == blockNumber. _safeMint reverts if already minted.
            _safeMint(msg.sender, blockNum);
            emit BlockMinted(msg.sender, blockNum);
        }
    }

    // ---------- Metadata ----------

    /// @notice Returns the data:application/json;base64,... URI for a token (pure on-chain)
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return PearlSVGRenderer.tokenURI(tokenId);
    }

    /// @notice Preview a token's URI even before minting (for frontend gallery)
    function previewURI(uint256 blockNumber) external pure returns (string memory) {
        require(blockNumber >= 1 && blockNumber <= MAX_SUPPLY, "Out of range");
        return PearlSVGRenderer.tokenURI(blockNumber);
    }

    /// @notice Check if a block is still available to mint
    function isAvailable(uint256 blockNumber) external view returns (bool) {
        if (blockNumber < 1 || blockNumber > MAX_SUPPLY) return false;
        return _ownerOf(blockNumber) == address(0);
    }

    /// @notice Batch availability check for frontend gallery
    function availableBatch(uint256 from, uint256 to) external view returns (bool[] memory) {
        require(to >= from && to <= MAX_SUPPLY && from >= 1, "Bad range");
        bool[] memory out = new bool[](to - from + 1);
        for (uint256 i = from; i <= to; i++) {
            out[i - from] = _ownerOf(i) == address(0);
        }
        return out;
    }

    // ---------- Admin ----------

    function setMintActive(bool _active) external onlyOwner {
        mintActive = _active;
        emit MintActiveChanged(_active);
    }

    function setPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
        emit PriceChanged(_price);
    }

    function setTreasury(address _t) external onlyOwner {
        require(_t != address(0), "Zero");
        treasury = _t;
        emit TreasuryChanged(_t);
    }

    /// @notice Emergency: withdraw any tokens sent to the contract by mistake
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /// @notice Emergency: withdraw any ETH sent by mistake (no payable functions, but just in case)
    function rescueETH(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "ETH send failed");
    }
}
