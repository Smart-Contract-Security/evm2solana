// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/// @title  clouds
/// @notice 333 generative pixel clouds. Token #N renders seed N in the on-seed engine.
///         Fully creator-owned ERC721A drop with on-chain royalties.
contract Clouds is ERC721A, ERC2981, Ownable {
    uint256 public constant MAX_SUPPLY = 666;
    uint256 public constant WL_MAX = 2;          // whitelist cap per wallet
    uint256 public price = 0.0033 ether;
    bool public saleActive;
    string private _baseTokenURI;

    // Two-phase timed sale. Set both once; the flip to public is automatic.
    //   block.timestamp <  wlTime               -> closed
    //   wlTime <= block.timestamp < publicTime   -> whitelist only, max WL_MAX each
    //   block.timestamp >= publicTime            -> public, no per-wallet cap
    uint256 public wlTime;
    uint256 public publicTime;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public wlMinted;

    // Shuffle offset: decouples tokenId from seed so mythics (fixed seeds) land on
    // random token ids. Locked once at launch from block randomness — nobody, not even
    // the first minter, can know or target which token will be a mythic.
    uint256 public startingIndex;
    bool public indexSet;

    constructor(string memory baseURI, address royaltyReceiver)
        ERC721A("clouds", "CLDS")
        Ownable(msg.sender)
    {
        _baseTokenURI = baseURI;
        _setDefaultRoyalty(royaltyReceiver, 500); // 5%
    }

    /// tokens are #1..#666; the seed each token renders is shuffled via startingIndex
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @notice The art seed a given token renders. tokenId is the mint order;
    ///         seedOf maps it (via the launch offset) to one of the 666 unique seeds.
    function seedOf(uint256 tokenId) public view returns (uint256) {
        return ((tokenId - 1 + startingIndex) % MAX_SUPPLY) + 1;
    }

    function _lockStartingIndex() internal {
        if (indexSet) return;
        startingIndex = (uint256(keccak256(abi.encodePacked(
            block.prevrandao, blockhash(block.number - 1), address(this)
        ))) % (MAX_SUPPLY - 1)) + 1;   // 1..665, never 0 so it always rotates
        indexSet = true;
    }

    function mint(uint256 quantity) external payable {
        require(saleActive, "sale not active");
        require(quantity > 0, "qty 0");
        require(wlTime != 0 && block.timestamp >= wlTime, "not started");
        require(_totalMinted() + quantity <= MAX_SUPPLY, "sold out");
        require(msg.value >= price * quantity, "wrong value");
        if (block.timestamp < publicTime) {
            // whitelist phase: flowers holders only, capped at WL_MAX
            require(whitelist[msg.sender], "not whitelisted");
            require(wlMinted[msg.sender] + quantity <= WL_MAX, "wl limit");
            wlMinted[msg.sender] += quantity;
        }
        _mint(msg.sender, quantity);
    }

    /// @notice 0 = closed, 1 = whitelist phase, 2 = public. For the mint UI.
    function phase() external view returns (uint8) {
        if (!saleActive || wlTime == 0 || block.timestamp < wlTime) return 0;
        if (block.timestamp < publicTime) return 1;
        return 2;
    }

    /// @notice Owner mint for reserves. Mints the next sequential ids, so calling
    ///         this before opening the sale lets you claim the iconic early tokens.
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "exceeds supply");
        _mint(to, quantity);
    }

    function setSaleActive(bool active) external onlyOwner { saleActive = active; }
    function setPrice(uint256 newPrice) external onlyOwner { price = newPrice; }

    /// @notice One-tap launch: opens whitelist mint NOW, public auto-flips in
    ///         exactly 2 hours. The contract does the flip on its own — no second tx.
    function goLive() external onlyOwner {
        _lockStartingIndex();
        saleActive = true;
        wlTime = block.timestamp;
        publicTime = block.timestamp + 2 hours;
    }

    /// @notice Schedule both phase times for a future announced launch.
    ///         e.g. setPhases(9pm, 11pm) for a 2-hour whitelist window.
    function setPhases(uint256 _wlTime, uint256 _publicTime) external onlyOwner {
        require(_publicTime >= _wlTime, "public before wl");
        _lockStartingIndex();
        wlTime = _wlTime;
        publicTime = _publicTime;
    }

    /// @notice Batch add/remove whitelist wallets (the flowers-holder snapshot).
    function setWhitelist(address[] calldata addrs, bool ok) external onlyOwner {
        for (uint256 i; i < addrs.length; i++) whitelist[addrs[i]] = ok;
    }
    function setBaseURI(string calldata uri) external onlyOwner { _baseTokenURI = uri; }
    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(receiver, bps);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, _toString(seedOf(tokenId)), ".json"));
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    /// @notice Collection-level metadata for marketplaces (OpenSea reads this).
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, "collection.json"));
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}
