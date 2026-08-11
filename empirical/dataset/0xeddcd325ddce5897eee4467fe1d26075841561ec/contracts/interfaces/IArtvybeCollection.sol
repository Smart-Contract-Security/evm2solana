// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IArtvybeCollection {
    // Events
    event TokenMinted(address indexed to, uint256 indexed tokenId, uint256 price);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MintingToggled(bool enabled);
    event BatchMintingToggled(bool enabled);
    event BaseURIUpdated(string oldURI, string newURI);
    event MintingCurrencyUpdated(address indexed oldCurrency, address indexed newCurrency);
    event CreatorFeeUpdated(uint96 oldFeeBps, uint96 newFeeBps);
    event MintStartTimeUpdated(uint256 oldStartTime, uint256 newStartTime);

    // Core functions
    function mint(address to, uint256 quantity) external payable;
    function setMintPrice(uint256 newPrice) external;
    function setMintingEnabled(bool enabled) external;
    function setBatchMinting(bool enabled) external;
    function setBaseURI(string memory newURI) external;
    function setMintingCurrency(address newCurrency) external;
    function setCreatorFeeBps(uint96 newFeeBps) external;
    function setMintStartTime(uint256 newStartTime) external;
    function tokenURI(uint256 tokenId) external view returns (string memory);
    
    // View functions
    function maxSupply() external view returns (uint256);
    function creatorFeeBps() external view returns (uint96);
    function mintingCurrency() external view returns (address);
    function mintPrice() external view returns (uint256);
    function mintingEnabled() external view returns (bool);
    function batchMintingAllowed() external view returns (bool);
    function mintStartTime() external view returns (uint256);
} 