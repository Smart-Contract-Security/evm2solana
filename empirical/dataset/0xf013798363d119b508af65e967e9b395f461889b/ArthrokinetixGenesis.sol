// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title Arthrokinetix Genesis Collection V3
 * @notice First on-chain medical-data-to-art NFT collection in history
 * @dev Fixed version with proper SVG encoding for OpenSea compatibility
 */
contract ArthrokinetixGenesisV3 is ERC721, ERC721Enumerable, Ownable {
    using Strings for uint256;
    
    // Struct to hold all NFT data
    struct TokenData {
        string name;
        string description;
        string svgData;
        string attributes;
        bool isArtwork;
        uint256 createdAt;
        string arweaveBackup;
    }
    
    // Mapping from token ID to token data
    mapping(uint256 => TokenData) public tokenData;
    
    // Counter for token IDs
    uint256 private _nextTokenId = 1;
    
    // Events
    event TokenMinted(uint256 indexed tokenId, address indexed to, bool isArtwork);
    
    constructor() ERC721("Arthrokinetix Genesis Collection V3", "ARTHRX3") Ownable(msg.sender) {}
    
    /**
     * @notice Mint a new artwork NFT with on-chain SVG storage
     */
    function mintArtwork(
        address to,
        string memory name,
        string memory description,
        string memory svgData,
        string memory attributes,
        string memory arweaveBackup
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        
        tokenData[tokenId] = TokenData({
            name: name,
            description: description,
            svgData: svgData,
            attributes: attributes,
            isArtwork: true,
            createdAt: block.timestamp,
            arweaveBackup: arweaveBackup
        });
        
        emit TokenMinted(tokenId, to, true);
        return tokenId;
    }
    
    /**
     * @notice Mint a new provenance NFT with on-chain JSON storage
     */
    function mintProvenance(
        address to,
        string memory name,
        string memory description,
        string memory provenanceJson,
        string memory arweaveBackup
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        
        // Create a simple SVG certificate for the provenance
        string memory provenanceSVG = string(abi.encodePacked(
            '<svg width="800" height="800" xmlns="http://www.w3.org/2000/svg">',
            '<rect width="800" height="800" fill="#2c3e50"/>',
            '<text x="400" y="100" font-family="Arial" font-size="32" fill="#3498db" text-anchor="middle">PROVENANCE CERTIFICATE</text>',
            '<text x="400" y="150" font-family="Arial" font-size="24" fill="#ecf0f1" text-anchor="middle">', name, '</text>',
            '<text x="400" y="400" font-family="Arial" font-size="18" fill="#3498db" text-anchor="middle">Token ID: ', tokenId.toString(), '</text>',
            '<text x="400" y="450" font-family="Arial" font-size="16" fill="#ecf0f1" text-anchor="middle">Blockchain Verified</text>',
            '</svg>'
        ));
        
        tokenData[tokenId] = TokenData({
            name: name,
            description: description,
            svgData: provenanceSVG,
            attributes: provenanceJson,
            isArtwork: false,
            createdAt: block.timestamp,
            arweaveBackup: arweaveBackup
        });
        
        emit TokenMinted(tokenId, to, false);
        return tokenId;
    }
    
    /**
     * @notice Get the SVG data for a token
     */
    function getSVG(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return tokenData[tokenId].svgData;
    }
    
    /**
     * @notice Get the attributes/provenance data for a token
     */
    function getAttributes(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return tokenData[tokenId].attributes;
    }
    
    /**
     * @notice Generate the complete tokenURI with properly encoded SVG
     * @dev CRITICAL: Base64 encode the SVG to avoid JSON parsing issues
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        TokenData memory data = tokenData[tokenId];
        
        // CRITICAL: Base64 encode the SVG first to handle quotes and special characters
        string memory svgBase64Encoded = Base64.encode(bytes(data.svgData));
        string memory imageDataURI = string(abi.encodePacked(
            "data:image/svg+xml;base64,",
            svgBase64Encoded
        ));
        
        // Build the metadata JSON
        string memory json;
        
        if (data.isArtwork) {
            json = string(abi.encodePacked(
                '{"name":"', data.name, '",',
                '"description":"', data.description, '",',
                '"image":"', imageDataURI, '",',  // Using "image" with data URI
                '"attributes":', data.attributes, ',',
                '"on_chain_storage":true,',
                '"arweave_backup":"', data.arweaveBackup, '",',
                '"created_at":', data.createdAt.toString(),
                '}'
            ));
        } else {
            json = string(abi.encodePacked(
                '{"name":"', data.name, '",',
                '"description":"', data.description, '",',
                '"image":"', imageDataURI, '",',  // Using "image" with data URI
                '"provenance_data":', data.attributes, ',',
                '"on_chain_storage":true,',
                '"arweave_backup":"', data.arweaveBackup, '",',
                '"created_at":', data.createdAt.toString(),
                '}'
            ));
        }
        
        // Base64 encode the complete JSON and return as data URI
        string memory base64json = Base64.encode(bytes(json));
        return string(abi.encodePacked('data:application/json;base64,', base64json));
    }
    
    /**
     * @notice Contract metadata for OpenSea
     */
    function contractURI() public pure returns (string memory) {
        string memory json = '{"name":"Arthrokinetix Genesis Collection V3","description":"The first on-chain medical-data-to-art NFT collection in history. V3 includes proper SVG encoding for full compatibility. Every piece is stored 100% on-chain.","image":"https://arthrokinetix.com/collection-banner.png","external_link":"https://arthrokinetix.com","seller_fee_basis_points":750,"fee_recipient":"0xYOUR_WALLET_ADDRESS"}';
        return string(abi.encodePacked('data:application/json;base64,', Base64.encode(bytes(json))));
    }
    
    // Required overrides
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 amount) 
        internal override(ERC721, ERC721Enumerable) 
    {
        super._increaseBalance(account, amount);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}