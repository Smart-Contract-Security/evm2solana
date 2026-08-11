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
    // Storage — v01/v02/v03 slots (do not reorder)
    // ─────────────────────────────────────────────

    uint256 private _nextTokenId;
    string  private _contractURI;

    uint256 public maxSupply;
    uint256 public currentMintPrice;
    uint256 public priceIncrement;
    string  public baseTokenURI;
    uint256 public maxPublicId;

    mapping(uint256 => bool) public tokenLocked;
    bool public soulbound;

    // ─────────────────────────────────────────────
    // Storage — v04 additions (appended, safe)
    // ─────────────────────────────────────────────

    // Overrides the ERC721 name() return value.
    // Set via reinitializeV4() during upgrade.
    // Allows ASCII-safe display on explorers (e.g. Etherscan) without
    // changing the on-chain UTF-8 bytes stored by ERC721Upgradeable.
    string private _nameOverride;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event PermanentURI(string _value, uint256 indexed _id);
    event ContractURIUpdated(string uri);
    event CollectionNameUpdated(string name);

    // ─────────────────────────────────────────────
    // Constructor & Initializer
    // ─────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // v01 initializer — not called again on upgrade, state preserved
    function initialize(address initialOwner) public initializer {
        __ERC721_init(unicode"DÜSSELPIX", "DPIX");
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __ERC2981_init();
        __Ownable_init(initialOwner);
        _setDefaultRoyalty(initialOwner, 700);
    }

    // v04 reinitializer — called once via upgradeToAndCall()
    // Sets the name override so explorers that mangle Unicode show ASCII.
    function reinitializeV4(string memory collectionName) public reinitializer(4) onlyOwner {
        _nameOverride = collectionName;
        emit CollectionNameUpdated(collectionName);
    }

    // ─────────────────────────────────────────────
    // Name Override
    // ─────────────────────────────────────────────

    // Returns _nameOverride if set, otherwise falls back to ERC721 name.
    function name() public view override returns (string memory) {
        if (bytes(_nameOverride).length > 0) return _nameOverride;
        return super.name();
    }

    // Owner can update the display name at any time.
    function setCollectionName(string calldata newName) external onlyOwner {
        _nameOverride = newName;
        emit CollectionNameUpdated(newName);
    }

    // ─────────────────────────────────────────────
    // URI Resolution
    // ─────────────────────────────────────────────

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    // ─────────────────────────────────────────────
    // Minting
    // ─────────────────────────────────────────────

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

    function airdrop(address[] calldata recipients, string[] calldata uris)
        external
        onlyOwner
    {
        require(recipients.length == uris.length, "DPIX: length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            safeMint(recipients[i], uris[i]);
        }
    }

    function publicMint() external payable {
        require(currentMintPrice > 0,                           "DPIX: mint not active");
        require(msg.value >= currentMintPrice,                  "DPIX: insufficient ETH");
        require(maxSupply == 0 || _nextTokenId < maxSupply,     "DPIX: max supply reached");
        require(maxPublicId == 0 || _nextTokenId < maxPublicId, "DPIX: public cap reached");

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);

        currentMintPrice = currentMintPrice * (10000 + priceIncrement) / 10000;
    }

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

    function setNextTokenId(uint256 newId) external onlyOwner {
        require(newId > _nextTokenId, "DPIX: cannot go backwards");
        _nextTokenId = newId;
    }

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

    function lockToken(uint256 tokenId) public onlyOwner {
        require(_ownerOf(tokenId) != address(0), "DPIX: nonexistent token");
        require(!tokenLocked[tokenId],            "DPIX: already locked");
        tokenLocked[tokenId] = true;
        emit PermanentURI(tokenURI(tokenId), tokenId);
    }

    // ─────────────────────────────────────────────
    // URI Management
    // ─────────────────────────────────────────────

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
