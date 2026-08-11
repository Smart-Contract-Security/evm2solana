// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title  BearlyBassToken
/// @notice ERC-721 collection for the Bearly Bass bass-loop project.
///         Fixed supply of 470 tokens = 94 loops x 5 audio keys.
///         Implements ERC-2981 (royalty info) at 250 bps (2.5%).
///
/// @dev Token-ID encoding (valid range: 1111 to 4105):
///        tokenId / 1000        => pricing tier (1-4; tier 4 is rarest)
///        tokenId % 10          => audio-key identifier (1-5)
///        (tokenId % 1000) / 10 => loop ID within tier
///          tier 4: loopId  1-10  (rarest, most expensive)
///          tier 1: loopId 11-36
///          tier 2: loopId 37-77
///          tier 3: loopId 78-94
///
/// @dev Pricing rules (see `getPrice` for the full table):
///        - The table holds the standard mint price for each token.
///        - Pre-threshold (mintCount < 47): tier-1 and tier-2 tokens are
///          sold at 10% of the listed price. Other tiers are unaffected.
///
/// @dev Owner powers (relevant for collectors evaluating trust):
///        - ownerMint:            mint for free while mintCount < 94
///                                (2 * mintThreshold). Intended for the
///                                owner to seed initial distribution
///                                (marketplace listings, gifts,
///                                collaborator allocations) — capped so
///                                the owner cannot retain free-mint
///                                privileges indefinitely.
///        - setBaseURI:           change metadata pointer, unless frozen.
///        - freezeBaseURI:        one-way; permanently locks metadata.
///        - setFollowUpContract:  one-shot pointer to a successor contract.
///        - abortFurtherMinting:  one-way; halts minting permanently. Only
///                                callable before mintCount reaches 235
///                                (MAX_SUPPLY / 2).
///        - withdraw:             sends entire contract balance to owner().
///        - renounceOwnership is permanently disabled (would lock funds).
///
/// @dev ERC-2981 royalty receiver is always the current `owner()` (250 bps,
///      i.e. 2.5%). `transferOwnership` moves the royalty stream with it —
///      there is no separate setter.
contract BearlyBassToken is ERC721, ERC2981, Ownable {
  uint256 public constant MAX_SUPPLY = 470;
  uint256 public constant mintThreshold = 47;
  uint256 public mintCount;
  string private baseURI;
  bool public baseURIFrozen;
  address public followUpContract;
  bool public furtherMintingAborted;

  // Events
  event TokenMinted(address indexed to, uint256 indexed tokenId, uint256 price);
  event SeriesMinted(address indexed to, uint256 indexed seriesId, uint256[] tokenIds, uint256 totalPrice);
  event BaseURIUpdated(string oldURI, string newURI);
  event BaseURIFrozen();
  event FollowUpContractSet(address indexed contractAddress);
  event FurtherMintingAborted();
  event Withdrawal(address indexed to, uint256 amount);

  /// @param _name             ERC-721 collection name.
  /// @param _symbol           ERC-721 collection symbol.
  /// @param _initialBaseURI   Base URI used to build `tokenURI(id)`.
  ///                          Mutable until `freezeBaseURI()` is called.
  constructor(
    string memory _name,
    string memory _symbol,
    string memory _initialBaseURI
  ) ERC721(_name, _symbol) Ownable(msg.sender) {
    baseURI = _initialBaseURI;
  }

  // ---------- Supply ----------
  /// @notice Returns the number of tokens minted so far
  /// @dev This equals the current circulating supply since tokens are non-burnable
  function totalSupply() external view returns (uint256) {
    return mintCount;
  }

  // ---------- Public Minting ----------
  function mint(uint256 tokenId) external payable mintable(tokenId) {
    uint256 price = getPrice(tokenId);
    require(msg.value == price, "Incorrect payment");

    mintCount++;
    _safeMint(msg.sender, tokenId);

    emit TokenMinted(msg.sender, tokenId, price);
  }

  function batchMintSeries(uint256 seriesId) external payable {
    (uint256 totalPrice, uint256[] memory tokenIds) = validateAndGetSeriesPrice(seriesId);
    require(msg.value == totalPrice, "Incorrect payment");

    // Mint all tokens. Re-check the supply cap on every iteration: `_safeMint`
    // hands control to the receiver via `onERC721Received`, which could
    // re-enter `mint`/`batchMintSeries` and push `mintCount` past `MAX_SUPPLY`
    // if we relied only on the up-front check in `validateAndGetSeriesPrice`.
    for (uint256 i = 0; i < 5; i++) {
      require(mintCount < MAX_SUPPLY, "Max supply reached");
      mintCount++;
      _safeMint(msg.sender, tokenIds[i]);
    }

    emit SeriesMinted(msg.sender, seriesId, tokenIds, totalPrice);
  }

  // ---------- Owner Mint (Free, Capped at 2x Threshold) ----------
  /// @notice Free mint reserved for the owner. Intended for seeding initial
  ///         distribution: listing tokens on marketplaces (e.g. OpenSea),
  ///         giveaways, and allocations to collaborators. Allowed only
  ///         while `mintCount < 94` (2 * mintThreshold), after which the
  ///         owner must pay the same price as any other minter.
  /// @param tokenId The ID of the token to mint.
  function ownerMint(uint256 tokenId) external onlyOwner mintable(tokenId) {
    require(mintCount < mintThreshold * 2, "Free owner minting ended");

    mintCount++;
    _safeMint(msg.sender, tokenId);

    emit TokenMinted(msg.sender, tokenId, 0);
  }

  // ---------- Pricing Logic ----------
  function getPrice(uint256 tokenId) public view onlyValidTokenId(tokenId) returns (uint256) {
    // Extract components from tokenId
    uint256 audioKeyIdentifier = tokenId % 10;
    uint256 pricingTier = tokenId / 1000;

    uint256 price;
    // Pricing table: the standard mint price for each token.
    if (audioKeyIdentifier == 1) {
      if (pricingTier == 1) price = 0.15 ether;
      if (pricingTier == 2) price = 0.4 ether;
      if (pricingTier == 3) price = 0.6 ether;
      if (pricingTier == 4) price = 1.05 ether;
    } else if (audioKeyIdentifier == 2) {
      if (pricingTier == 1) price = 0.3 ether;
      if (pricingTier == 2) price = 0.75 ether;
      if (pricingTier == 3) price = 1.2 ether;
      if (pricingTier == 4) price = 2.1 ether;
    } else if (audioKeyIdentifier == 3) {
      if (pricingTier == 1) price = 0.45 ether;
      if (pricingTier == 2) price = 1.1 ether;
      if (pricingTier == 3) price = 1.8 ether;
      if (pricingTier == 4) price = 3.15 ether;
    } else if (audioKeyIdentifier == 4) {
      if (pricingTier == 1) price = 0.75 ether;
      if (pricingTier == 2) price = 1.9 ether;
      if (pricingTier == 3) price = 3.0 ether;
      if (pricingTier == 4) price = 5.25 ether;
    } else if (audioKeyIdentifier == 5) {
      if (pricingTier == 1) price = 1.2 ether;
      if (pricingTier == 2) price = 3.0 ether;
      if (pricingTier == 3) price = 4.8 ether;
      if (pricingTier == 4) price = 8.4 ether;
    } else {
      revert("Invalid token ID");
    }

    // Before mint threshold, tier-1 and tier-2 tokens are sold at 10% of
    // the listed price.
    if (mintCount < mintThreshold && (pricingTier == 1 || pricingTier == 2)) {
      return price / 10;
    }

    return price;
  }

  /// @dev Pricing is snapshotted at call time: `getPrice` reads the current
  ///      `mintCount` once per token in the batch. A batch that starts with
  ///      `mintCount < mintThreshold` therefore prices all five tier-1/tier-2
  ///      tokens at the 10% pre-threshold discount, even if minting the
  ///      batch itself causes `mintCount` to cross `mintThreshold`. This is
  ///      intended — the discount is locked in for the buyer who triggers
  ///      the threshold crossing.
  function validateAndGetSeriesPrice(
    uint256 seriesId
  ) public view returns (uint256 totalPrice, uint256[] memory tokenIds) {
    require(!furtherMintingAborted, "Further minting permanently stopped");
    require(mintCount + 5 <= MAX_SUPPLY, "Max supply would be exceeded");

    tokenIds = new uint256[](5);
    totalPrice = 0;

    // Calculate total price and check availability
    for (uint256 i = 0; i < 5; i++) {
      uint256 tokenId = seriesId * 10 + i + 1;
      require(isValidTokenId(tokenId), "Invalid series ID");
      require(_ownerOf(tokenId) == address(0), "Token already minted");
      totalPrice += getPrice(tokenId);
      tokenIds[i] = tokenId;
    }
  }

  // ---------- Series Owner Check ----------
  function seriesHasUniqueOwner(uint256 tokenId) public view onlyValidTokenId(tokenId) returns (bool) {
    // Extract the series identifier (first 3 digits)
    uint256 seriesId = tokenId / 10;

    // Check if all tokens in the series are minted and have the same owner
    address firstOwner = address(0);
    for (uint256 i = 0; i < 5; i++) {
      uint256 id = seriesId * 10 + i + 1;
      address owner = _ownerOf(id);
      if (owner == address(0)) {
        return false;
      }
      if (i == 0) {
        firstOwner = owner;
      } else if (owner != firstOwner) {
        return false;
      }
    }

    return true;
  }

  // ---------- Metadata / Royalty / Admin ----------

  function setBaseURI(string memory _newBaseURI) external onlyOwner {
    require(!baseURIFrozen, "Base URI is frozen");
    bytes memory uriBytes = bytes(_newBaseURI);
    require(uriBytes.length > 0, "Base URI cannot be empty");
    require(uriBytes[uriBytes.length - 1] == 0x2f, "Base URI must end with /");
    string memory oldURI = baseURI;
    baseURI = _newBaseURI;
    emit BaseURIUpdated(oldURI, _newBaseURI);
  }

  function freezeBaseURI() external onlyOwner {
    require(!baseURIFrozen, "Base URI already frozen");
    baseURIFrozen = true;
    emit BaseURIFrozen();
  }

  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  /// @notice Returns the current base URI used for token metadata
  /// @return The current base URI string
  function getBaseURI() external view returns (string memory) {
    return baseURI;
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireOwned(tokenId);
    return bytes(baseURI).length > 0 ? string.concat(baseURI, Strings.toString(tokenId), ".json") : "";
  }

  /// @notice Sets a follow-up contract address. Can only be set once to any non-zero address.
  /// @dev Used for additional future features on top, or for follow-ups in case minting was aborted in this contract.
  ///      Once set, cannot be changed.
  function setFollowUpContract(address _followUpContract) external onlyOwner {
    require(followUpContract == address(0), "Follow up contract already set");
    require(_followUpContract != address(0), "Cannot set null address as follow up");
    followUpContract = _followUpContract;
    emit FollowUpContractSet(_followUpContract);
  }

  /// @notice Permanently stops further minting in this contract.
  /// @dev This option can be used if:
  ///      1. The project finds no community interest
  ///      2. New technical possibilities evolve to combine with art
  ///      3. The project needs to pivot to a different direction
  ///      Can only be called once before mintCount reaches MAX_SUPPLY/2.
  function abortFurtherMinting() external onlyOwner {
    require(!furtherMintingAborted, "Further minting already aborted");
    require(mintCount < MAX_SUPPLY / 2, "Too many tokens minted to abort further minting");
    furtherMintingAborted = true;
    emit FurtherMintingAborted();
  }

  function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  function withdraw() external onlyOwner {
    uint256 amount = address(this).balance;
    (bool success, ) = payable(owner()).call{value: amount}("");
    require(success, "Withdraw failed");
    emit Withdrawal(owner(), amount);
  }

  /// @notice ERC-2981 royalty info. Receiver is always the current `owner()`
  ///         (so `transferOwnership` moves the royalty stream with it). Rate
  ///         is fixed at 250 bps (2.5%) of the sale price.
  function royaltyInfo(
    uint256,
    uint256 salePrice
  ) public view virtual override returns (address receiver, uint256 royaltyAmount) {
    return (owner(), (salePrice * 250) / 10000);
  }

  /// @notice Permanently disabled. Renouncing ownership would leave any contract
  ///         ETH unwithdrawable (no other route exists). Withdraw first, then
  ///         transferOwnership if the owner key needs to change.
  function renounceOwnership() public pure override {
    revert("Renouncing ownership disabled");
  }

  // ---------- Mint Count Getter ----------
  function getMintCount() external view returns (uint256) {
    return mintCount;
  }

  // ---------- Token ID Validation ----------
  function isValidTokenId(uint256 tokenId) public pure returns (bool) {
    // Quick range check - bail out early for IDs outside the valid range
    if (tokenId < 1111 || tokenId > 4105) {
      return false;
    }

    // Extract components from tokenId
    uint256 audioKeyIdentifier = tokenId % 10;
    uint256 pricingTier = tokenId / 1000;
    uint256 loopId = (tokenId % 1000) / 10;

    // Check if audioKeyIdentifier is in valid range (1-5)
    if (audioKeyIdentifier < 1 || audioKeyIdentifier > 5) {
      return false;
    }

    // Check if pricingTier is in valid range (1-4)
    if (pricingTier < 1 || pricingTier > 4) {
      return false;
    }

    // Check if loopId is in valid range based on pricing tier
    if (pricingTier == 4) {
      if (loopId < 1 || loopId > 10) {
        return false;
      }
    } else if (pricingTier == 1) {
      if (loopId < 11 || loopId > 36) {
        return false;
      }
    } else if (pricingTier == 2) {
      if (loopId < 37 || loopId > 77) {
        return false;
      }
    } else if (pricingTier == 3) {
      if (loopId < 78 || loopId > 94) {
        return false;
      }
    }

    return true;
  }

  modifier onlyValidTokenId(uint256 tokenId) {
    require(isValidTokenId(tokenId), "Invalid token ID");
    _;
  }

  modifier mintable(uint256 tokenId) {
    require(!furtherMintingAborted, "Further minting permanently stopped");
    require(isValidTokenId(tokenId), "Invalid token ID");
    require(_ownerOf(tokenId) == address(0), "Token already minted");
    require(mintCount < MAX_SUPPLY, "Max supply reached");
    _;
  }
}
