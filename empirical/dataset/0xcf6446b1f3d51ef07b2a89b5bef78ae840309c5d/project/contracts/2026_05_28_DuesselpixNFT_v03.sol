// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity 0.8.34;
/*
  _____  _____  _______   __
 |  __ \|  __ \_   _\ \ / /
 | |  | | |__) || |  \ V /
 | |  | |  ___/ | |   > <
 | |__| | |    _| |_ / . \
 |_____/|_|   |_____/_/ \_\

 #DUESSELPIX — Mixed Material Arts on Chain
 ERC-721 Upgradeable (UUPS) · Irys / Arweave · EIP-2981 Royalties
 by doncapri.eth
*/

import {Initializable}               from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable}             from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable}          from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721Upgradeable}           from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable}   from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC2981Upgradeable}          from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";

contract DuesselpixNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ─────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────

    uint256 private _nextTokenId;
    string  private _contractURI;

    // ─────────────────────────────────────────────
    // Supply & Mint Config
    // ─────────────────────────────────────────────

    uint256 public maxSupply;        // 0 = unlimited
    uint256 public currentMintPrice; // in wei; 0 = public mint disabled
    uint256 public priceIncrement;   // basis points — 700 = 7%
    string  public baseTokenURI;     // Irys/Arweave manifest root, e.g. "ar://xyz123/"
    uint256 public maxPublicId;      // upper token-ID limit for public mint (0 = unlimited)

    // ─────────────────────────────────────────────
    // Lock & Soulbound
    // ─────────────────────────────────────────────

    mapping(uint256 => bool) public tokenLocked;
    bool public soulbound;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event PermanentURI(string _value, uint256 indexed _id);
    event ContractURIUpdated(string uri);

    // ─────────────────────────────────────────────
    // Constructor & Initializer
    // ─────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __ERC721_init(unicode"DÜSSELPIX", "DPIX");
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __ERC2981_init();
        __Ownable_init(initialOwner);
        _setDefaultRoyalty(initialOwner, 700); // 7% royalty
    }

    // ─────────────────────────────────────────────
    // URI Resolution
    //
    // How token URIs resolve:
    //   baseTokenURI = "ar://xyz123/"
    //   tokenURI(42) → "ar://xyz123/42"
    //
    // Exception: if a per-token override was set via setTokenURI(),
    // that override takes precedence over baseURI + tokenId.
    // ─────────────────────────────────────────────

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    // ─────────────────────────────────────────────
    // Minting
    // ─────────────────────────────────────────────

    // Owner mint: single token with individual Irys/Arweave URI.
    // uri = "" → token resolves via baseTokenURI + tokenId (no override set).
    function safeMint(address to, string memory uri)
        public
        onlyOwner
        returns (uint256)
    {
        require(maxSupply == 0 || _nextTokenId < maxSupply, "DPIX: max supply reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        if (bytes(uri).length > 0) {
            _setTokenURI(tokenId, uri);
        }
        return tokenId;
    }

    // Owner mint: multiple tokens in a single transaction, all to one address.
    function batchMint(address to, string[] memory uris)
        public
        onlyOwner
        returns (uint256[] memory)
    {
        uint256[] memory tokenIds = new uint256[](uris.length);
        for (uint256 i = 0; i < uris.length; i++) {
            tokenIds[i] = safeMint(to, uris[i]);
        }
        return tokenIds;
    }

    // Airdrop: mint one token per recipient, each to a different address.
    // recipients[i] receives a token with uris[i] as metadata URI.
    // uri = "" → resolves via baseTokenURI + tokenId.
    function airdrop(address[] calldata recipients, string[] calldata uris)
        external
        onlyOwner
    {
        require(recipients.length == uris.length, "DPIX: length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            safeMint(recipients[i], uris[i]);
        }
    }

    // Public mint: bonding curve — each buyer pays slightly more than the previous.
    // Token URI resolves automatically via baseTokenURI + tokenId (no _setTokenURI needed).
    // Prerequisite: setMintConfig() must be called by the owner beforehand.
    function publicMint() external payable {
        require(currentMintPrice > 0,                           "DPIX: mint not active");
        require(msg.value >= currentMintPrice,                  "DPIX: insufficient ETH");
        require(maxSupply == 0 || _nextTokenId < maxSupply,     "DPIX: max supply reached");
        require(maxPublicId == 0 || _nextTokenId < maxPublicId, "DPIX: public cap reached");

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        // Bonding curve: raise price for the next buyer
        currentMintPrice = currentMintPrice * (10000 + priceIncrement) / 10000;
    }

    // Returns the price the NEXT buyer will pay (after the current token is minted).
    // The current buyer's price is currentMintPrice.
    function priceAfterMint() external view returns (uint256) {
        return currentMintPrice * (10000 + priceIncrement) / 10000;
    }

    // ─────────────────────────────────────────────
    // Supply & Mint Config
    // ─────────────────────────────────────────────

    function setMaxSupply(uint256 cap) external onlyOwner {
        require(cap == 0 || cap >= _nextTokenId, "DPIX: below current supply");
        maxSupply = cap;
    }

    // Reserves a token-ID block (e.g. IDs 0–9 for owner reserve).
    // Next safeMint/publicMint will start from the new ID.
    function setNextTokenId(uint256 newId) external onlyOwner {
        require(newId > _nextTokenId, "DPIX: cannot go backwards");
        _nextTokenId = newId;
    }

    // Activates / configures public mint.
    // startPrice in wei (1 ETH = 1e18 wei).
    // _priceIncrement in basis points (700 = 7%).
    // _baseTokenURI e.g. "ar://abc123/" — all tokens resolve as baseTokenURI + tokenId.
    // _maxPublicId: highest token-ID available for public mint (0 = no limit).
    function setMintConfig(
        uint256         startPrice,
        uint256         _priceIncrement,
        string calldata _baseTokenURI,
        uint256         _maxPublicId
    ) external onlyOwner {
        currentMintPrice = startPrice;
        priceIncrement   = _priceIncrement;
        baseTokenURI     = _baseTokenURI;
        maxPublicId      = _maxPublicId;
    }

    // ─────────────────────────────────────────────
    // Admin | Multi Configure
    // ─────────────────────────────────────────────

    function multiConfigure(
        string     calldata newContractURI,
        address             royaltyReceiver,
        uint96              royaltyFee,
        uint256[]  calldata tokenIds,
        string[]   calldata uris
    ) external onlyOwner {
        if (bytes(newContractURI).length > 0) {
            _contractURI = newContractURI;
            emit ContractURIUpdated(newContractURI);
        }
        if (royaltyReceiver != address(0)) {
            _setDefaultRoyalty(royaltyReceiver, royaltyFee);
        }
        if (tokenIds.length > 0) {
            require(tokenIds.length == uris.length, "DPIX: length mismatch");
            for (uint256 i = 0; i < tokenIds.length; i++) {
                if (bytes(uris[i]).length > 0) {
                    _setTokenURI(tokenIds[i], uris[i]);
                    emit MetadataUpdate(tokenIds[i]);
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // Lock Management
    // ─────────────────────────────────────────────

    // Permanently freeze a token: URI can no longer be changed.
    // Also emits the PermanentURI event (OpenSea standard for "frozen metadata").
    function lockToken(uint256 tokenId) public onlyOwner {
        require(_ownerOf(tokenId) != address(0), "DPIX: nonexistent token");
        require(!tokenLocked[tokenId],            "DPIX: already locked");
        tokenLocked[tokenId] = true;
        emit PermanentURI(tokenURI(tokenId), tokenId);
    }

    // ─────────────────────────────────────────────
    // URI Management
    // ─────────────────────────────────────────────

    // Overrides the URI of a single token (e.g. after a metadata update on Irys/Arweave).
    // Locked tokens cannot be modified.
    function setTokenURI(uint256 tokenId, string memory uri) public onlyOwner {
        require(!tokenLocked[tokenId], "DPIX: token is permanently locked");
        _setTokenURI(tokenId, uri);
        emit MetadataUpdate(tokenId);
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory uri) public onlyOwner {
        _contractURI = uri;
        emit ContractURIUpdated(uri);
    }

    // ─────────────────────────────────────────────
    // Royalty Management
    // ─────────────────────────────────────────────

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        require(!tokenLocked[tokenId], "DPIX: token is permanently locked");
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    // ─────────────────────────────────────────────
    // Soulbound
    // ─────────────────────────────────────────────

    // Soulbound = token cannot be transferred or burned after mint.
    // Useful for collector badges or proof-of-ownership without resale.
    function setSoulbound(bool enabled) external onlyOwner {
        soulbound = enabled;
    }

    // ─────────────────────────────────────────────
    // Read
    // ─────────────────────────────────────────────

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    function mintActive() external view returns (bool) {
        return currentMintPrice > 0;
    }

    // ─────────────────────────────────────────────
    // Withdraw
    // ─────────────────────────────────────────────

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "DPIX: withdraw failed");
    }

    // ─────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Soulbound guard: blocks transfers and burns after mint.
    // auth == address(0) means mint — always allowed through.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable)
        returns (address)
    {
        if (soulbound && auth != address(0)) {
            revert("DPIX: soulbound - transfers disabled");
        }
        return super._update(to, tokenId, auth);
    }

    // ─────────────────────────────────────────────
    // Overrides (Solidity Multi-Inheritance)
    // ─────────────────────────────────────────────

    function tokenURI(uint256 tokenId)
        public view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
