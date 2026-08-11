// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Ten Thousand V2 — freemium mint with per-wallet cap
/// @notice 10,000 ERC-721 pixels. First 10 mints per wallet are free.
///         Mints 11–100 cost `mintPriceWei` each. Mints beyond 100 per wallet
///         are rejected on-chain. Owner can update `mintPriceWei`.
contract TenThousandV2 is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant GRID_SIZE = 100;
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice First N mints per wallet are free
    uint256 public constant FREE_PER_WALLET = 10;
    /// @notice Hard cap per wallet (free + paid combined). Cannot be exceeded.
    uint256 public constant MAX_PER_WALLET = 100;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Price per pixel for mints BEYOND the free tier, in wei
    uint256 public mintPriceWei;
    uint256 public totalMinted;
    string public contractMetadataURI;
    string private _baseTokenURI;
    bool public mintOpen;

    /// @notice Lifetime mint count per wallet — transfers do NOT reduce this
    mapping(address => uint256) public mintedBy;

    /*//////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/

    event PixelMinted(address indexed to, uint256 indexed tokenId, uint256 paidWei);
    event MintStateChanged(bool open);
    event MintPriceChanged(uint256 newPriceWei);
    event BaseURIChanged(string newBaseURI);

    /*//////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////*/

    error MintNotOpen();
    error AlreadyMinted(uint256 tokenId);
    error InvalidTokenId(uint256 tokenId);
    error InsufficientPayment(uint256 required, uint256 provided);
    error BatchTooLarge();
    error EmptyBatch();
    error ExceedsWalletCap(uint256 alreadyMinted, uint256 requested, uint256 cap);
    error WithdrawFailed();
    error RefundFailed();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 _mintPriceWei,
        string memory baseURI_,
        address _royaltyReceiver,
        uint96 _royaltyBps,
        string memory _contractURI
    ) ERC721("Ten Thousand", "10K") Ownable(msg.sender) {
        mintPriceWei = _mintPriceWei;
        _baseTokenURI = baseURI_;
        contractMetadataURI = _contractURI;
        _setDefaultRoyalty(_royaltyReceiver, _royaltyBps);
    }

    /*//////////////////////////////////////////////////////////////
                                  MINTING
    //////////////////////////////////////////////////////////////*/

    function mint(uint256 tokenId) external payable nonReentrant {
        if (!mintOpen) revert MintNotOpen();
        if (tokenId >= MAX_SUPPLY) revert InvalidTokenId(tokenId);
        if (_ownerOf(tokenId) != address(0)) revert AlreadyMinted(tokenId);

        uint256 alreadyMinted = mintedBy[msg.sender];
        if (alreadyMinted + 1 > MAX_PER_WALLET) {
            revert ExceedsWalletCap(alreadyMinted, 1, MAX_PER_WALLET);
        }

        uint256 price = alreadyMinted < FREE_PER_WALLET ? 0 : mintPriceWei;
        if (msg.value < price) revert InsufficientPayment(price, msg.value);

        _safeMint(msg.sender, tokenId);
        unchecked {
            totalMinted += 1;
            mintedBy[msg.sender] = alreadyMinted + 1;
        }
        emit PixelMinted(msg.sender, tokenId, price);

        if (msg.value > price) {
            (bool ok, ) = msg.sender.call{value: msg.value - price}("");
            if (!ok) revert RefundFailed();
        }
    }

    function mintBatch(uint256[] calldata tokenIds) external payable nonReentrant {
        if (!mintOpen) revert MintNotOpen();
        uint256 n = tokenIds.length;
        if (n == 0) revert EmptyBatch();
        if (n > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 alreadyMinted = mintedBy[msg.sender];
        if (alreadyMinted + n > MAX_PER_WALLET) {
            revert ExceedsWalletCap(alreadyMinted, n, MAX_PER_WALLET);
        }

        // How many of the N mints in this batch fall in the free tier?
        uint256 freeRem = alreadyMinted < FREE_PER_WALLET
            ? FREE_PER_WALLET - alreadyMinted
            : 0;
        uint256 freeInBatch = freeRem < n ? freeRem : n;
        uint256 paidInBatch = n - freeInBatch;
        uint256 perPaid = mintPriceWei;
        uint256 total = paidInBatch * perPaid;
        if (msg.value < total) revert InsufficientPayment(total, msg.value);

        for (uint256 i = 0; i < n; ) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= MAX_SUPPLY) revert InvalidTokenId(tokenId);
            if (_ownerOf(tokenId) != address(0)) revert AlreadyMinted(tokenId);
            _safeMint(msg.sender, tokenId);
            // Per-pixel emit reflecting the actual price tier
            uint256 thisPrice = i < freeInBatch ? 0 : perPaid;
            emit PixelMinted(msg.sender, tokenId, thisPrice);
            unchecked { ++i; }
        }
        unchecked {
            totalMinted += n;
            mintedBy[msg.sender] = alreadyMinted + n;
        }

        if (msg.value > total) {
            (bool ok, ) = msg.sender.call{value: msg.value - total}("");
            if (!ok) revert RefundFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Free mints still available for a wallet (out of FREE_PER_WALLET)
    function freeMintsRemaining(address wallet) external view returns (uint256) {
        uint256 used = mintedBy[wallet];
        if (used >= FREE_PER_WALLET) return 0;
        return FREE_PER_WALLET - used;
    }

    /// @notice Total mints still available for a wallet (out of MAX_PER_WALLET)
    function mintsRemaining(address wallet) external view returns (uint256) {
        uint256 used = mintedBy[wallet];
        if (used >= MAX_PER_WALLET) return 0;
        return MAX_PER_WALLET - used;
    }

    /// @notice Total wei a wallet would have to send to mint `count` pixels
    function quotePrice(address wallet, uint256 count) external view returns (uint256) {
        uint256 used = mintedBy[wallet];
        uint256 freeRem = used < FREE_PER_WALLET ? FREE_PER_WALLET - used : 0;
        uint256 freeInBatch = freeRem < count ? freeRem : count;
        uint256 paidInBatch = count - freeInBatch;
        return paidInBatch * mintPriceWei;
    }

    /*//////////////////////////////////////////////////////////////
                              TOKEN URI
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(_baseTokenURI, tokenId.toString());
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function contractURI() external view returns (string memory) {
        return contractMetadataURI;
    }

    /*//////////////////////////////////////////////////////////////
                              COORD HELPERS
    //////////////////////////////////////////////////////////////*/

    function coords(uint256 tokenId) public pure returns (uint256 x, uint256 y) {
        x = tokenId % GRID_SIZE;
        y = tokenId / GRID_SIZE;
    }

    function tokenIdFromCoords(uint256 x, uint256 y) public pure returns (uint256) {
        require(x < GRID_SIZE && y < GRID_SIZE, "out of bounds");
        return y * GRID_SIZE + x;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    function setMintOpen(bool _open) external onlyOwner {
        mintOpen = _open;
        emit MintStateChanged(_open);
    }

    function setMintPriceWei(uint256 _price) external onlyOwner {
        mintPriceWei = _price;
        emit MintPriceChanged(_price);
    }

    function setBaseURI(string calldata _uri) external onlyOwner {
        _baseTokenURI = _uri;
        emit BaseURIChanged(_uri);
    }

    function setContractURI(string calldata _uri) external onlyOwner {
        contractMetadataURI = _uri;
    }

    function setDefaultRoyalty(address receiver, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(receiver, bps);
    }

    function withdraw(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        if (!ok) revert WithdrawFailed();
    }

    /*//////////////////////////////////////////////////////////////
                              INTERFACE SUPPORT
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
