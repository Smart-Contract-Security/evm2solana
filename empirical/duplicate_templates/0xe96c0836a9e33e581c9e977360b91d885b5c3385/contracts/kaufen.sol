// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;


import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { ERC721C } from "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import { ERC721OpenZeppelin } from "@limitbreak/creator-token-standards/src/token/erc721/ERC721OpenZeppelin.sol";
import {
    BasicRoyalties,
    ERC2981
} from "@limitbreak/creator-token-standards/src/programmable-royalties/BasicRoyalties.sol";




contract Kaufen is ERC721C, BasicRoyalties, OwnableBasic {
    uint256 private _currentIndex;

    mapping(address => bool) public minterAddresses;
    mapping(address => bool) public hasFreeMinted;

    error InsufficientPayment();
    error SoldOut();
    error NoScripts();
    error NotApprovedOrOwner();
    error NotMinter();
    error ExceedsMaxSupply();
    error URIQueryForNonExistentToken();
    error MintZeroQuantity();
    error AlreadyFreeMinted();
    error FreeMintNotActive();

    event MinterAddressSet(address indexed minter, bool allowed);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
    event FreeMintClaimed(address indexed minter, uint256 tokenId);

    modifier noContracts() {
        if (tx.origin != msg.sender) revert NoScripts();
        _;
    }

    uint256 public constant MAX_SUPPLY = 555;
    uint256 public constant COST = 0.0002 ether;
    string public constant NAME = "Kaufen";
    string public constant SYMBOL = "Kaufen";
    string private __baseURI = "bafybeidz6eg3qyrpjbajngdr332qkpe7qdjixcrpea2pkwpdmnuclw4f74";
    
    bool public freeMintActive = true;

    constructor(
    ) ERC721OpenZeppelin(NAME, SYMBOL) OwnableBasic() BasicRoyalties(msg.sender, 500) {
        _currentIndex = 1; // Start token IDs at 1
    }

    // ============ FREE MINT FUNCTION ============

    function freeMint() external noContracts {
        // Check if free mint is active
        if (!freeMintActive) revert FreeMintNotActive();
        
        // Check if wallet has already claimed
        if (hasFreeMinted[msg.sender]) revert AlreadyFreeMinted();
        
        // Check supply
        if (_currentIndex > MAX_SUPPLY) revert ExceedsMaxSupply();
        
        // Mark as claimed
        hasFreeMinted[msg.sender] = true;
        
        // Get token ID and increment
        uint256 tokenId = _currentIndex;
        unchecked { ++_currentIndex; }
        
        // Mint token
        _mint(msg.sender, tokenId);
        
        emit FreeMintClaimed(msg.sender, tokenId);
    }

    // ============ PAID MINT FUNCTION ============

    function mint(uint256 quantity) external payable noContracts {
        if (quantity == 0) revert MintZeroQuantity();
        
        uint256 startTokenId = _currentIndex;
        
        // Check supply in a single condition
        if (startTokenId + quantity - 1 > MAX_SUPPLY) revert ExceedsMaxSupply();
        
        // Check payment
        if (msg.value < COST * quantity) revert InsufficientPayment();
        
        // Update index once
        _currentIndex += quantity;
        
        // Mint tokens in loop - gas efficient batch minting
        uint256 endTokenId = startTokenId + quantity;
        for (uint256 i = startTokenId; i < endTokenId;) {
            _mint(msg.sender, i);
            unchecked { ++i; }
        }
    }

    // ============ OWNER FUNCTIONS ============

    function setFreeMintActive(bool _active) external onlyOwner {
        freeMintActive = _active;
    }

    function setRoyaltyInfo(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success);
    }

    // ============ VIEW FUNCTIONS ============

    function totalSupply() external view returns (uint256) {
        return _currentIndex - 1; // Subtract 1 because index starts at 1
    }

    function tokenURI(uint256 tokenId) public override view returns (string memory) {
        return string(abi.encodePacked("ipfs://", __baseURI, "/", _toString(tokenId), ".json"));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721C, ERC2981) returns (bool) {
        return ERC721C.supportsInterface(interfaceId) || super.supportsInterface(interfaceId);
    }

    // ============ BURN FUNCTION ============

    function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), NotApprovedOrOwner());
        _burn(tokenId);
    }

    // ============ UTILS ============

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            buffer[--digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }
}
