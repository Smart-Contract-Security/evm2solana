// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "solady/src/tokens/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MethMiners
 * @dev ERC721 token representing Meth miners with fully on-chain metadata
 */
contract MethMiners is ERC721, Ownable, ERC2981 {
    using Strings for uint256;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @dev Token ID counter
    uint256 private _tokenIdCounter;

    /// @dev Address of the MethMiningSystem contract (authorized minter)
    address public miningContract;

    /// @dev Additional authorized minters (e.g. Packs contract)
    mapping(address => bool) public authorizedMinters;

    /// @dev Struct to store miner data
    struct MinerData {
        uint32 minerId;        // Original miner ID from the game
        uint8 minerIndex;     // Miner type/template index
        uint32 hashrate;       // Mining power
        uint32 powerConsumption; // Power required
    }

    /// @dev Struct to store miner template metadata
    struct MinerTemplate {
        string name;            // Name of the miner type
        string imageData;       // Base64 encoded image data
        uint32 baseHashrate;    // Template base hashrate; used to derive a token's rarity tier from its final hashrate
        bool exists;            // Whether this template has been set
    }

    /// @dev Background image data keyed by rarity multiplier (100=Common, 125=Rare, 150=Epic, 200=Mythic).
    mapping(uint8 => string) public rarityBackgrounds;

    /// @dev Mapping from token ID to miner data
    mapping(uint256 => MinerData) public minerData;

    /// @dev Mapping from miner index to template metadata
    mapping(uint256 => MinerTemplate) public minerTemplates;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            EVENTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    event MinerMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint32 minerId,
        uint8 minerIndex,
        uint32 hashrate,
        uint32 powerConsumption
    );

    event MinerBurned(uint256 indexed tokenId, uint256 minerId);

    event MiningContractUpdated(address indexed oldContract, address indexed newContract);

    event MinerTemplateAdded(uint256 indexed minerIndex, string name);

    event MinerTemplateUpdated(uint256 indexed minerIndex, string name);

    event AuthorizedMinterUpdated(address indexed minter, bool authorized);

    event RarityBackgroundUpdated(uint8 indexed rarity);

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            ERRORS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    error OnlyMiningContract();
    error InvalidMinerData();
    error TokenDoesNotExist();
    error MinerTemplateNotSet();
    error OnlyOwner();
    error InvalidRarity();

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //          CONSTRUCTOR
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    constructor() ERC721("Meth Miners", "METH") Ownable(msg.sender) {_setDefaultRoyalty(msg.sender, 500);}

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //          MODIFIERS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    modifier onlyMiningContract() {
        if (msg.sender != miningContract && !authorizedMinters[msg.sender]) revert OnlyMiningContract();
        _;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        MINTING FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * @dev Mint a new miner NFT. Can only be called by the mining contract.
     * @param to Address to mint the NFT to
     * @param minerId Original miner ID from the game
     * @param minerIndex Miner type/template index
     * @param hashrate Mining power of the miner
     * @param powerConsumption Power consumption of the miner
     * @return tokenId The ID of the newly minted token
     */
    function mintMinerNFT(
        address to,
        uint32 minerId,
        uint8 minerIndex,
        uint32 hashrate,
        uint32 powerConsumption
    ) external onlyMiningContract returns (uint256) {
        if (to == address(0)) revert InvalidMinerData();
        if (minerIndex == 0) revert InvalidMinerData();
        if (!minerTemplates[minerIndex].exists) revert MinerTemplateNotSet();

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _safeMint(to, tokenId);

        minerData[tokenId] = MinerData({
            minerId: minerId,
            minerIndex: minerIndex,
            hashrate: hashrate,
            powerConsumption: powerConsumption
        });

        emit MinerMinted(to, tokenId, minerId, minerIndex, hashrate, powerConsumption);

        return tokenId;
    }

    /**
     * @dev Burn a miner NFT. Can only be called by the token owner.
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) external {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) revert TokenDoesNotExist();
        
        // Only the owner can burn their token
        if (msg.sender != owner) {
            revert OnlyOwner();
        }

        uint256 minerId = minerData[tokenId].minerId;
        delete minerData[tokenId];

        _burn(tokenId);

        emit MinerBurned(tokenId, minerId);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //      METADATA FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * @dev Add or update a miner template
     * @param minerIndex The miner type index
     * @param name The name of the miner type
     * @param imageData Base64 encoded image data (should include data:image/... prefix)
     */
    function setMinerTemplate(
        uint8 minerIndex,
        string memory name,
        string memory imageData,
        uint32 baseHashrate
    ) external onlyOwner {
        bool exists = minerTemplates[minerIndex].exists;

        minerTemplates[minerIndex] = MinerTemplate({
            name: name,
            imageData: imageData,
            baseHashrate: baseHashrate,
            exists: true
        });

        if (exists) {
            emit MinerTemplateUpdated(minerIndex, name);
        } else {
            emit MinerTemplateAdded(minerIndex, name);
        }
    }

    /**
     * @dev Generate the full metadata JSON for a token
     * @param tokenId The token ID
     * @return The complete metadata JSON as a string
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        MinerData memory data = minerData[tokenId];
        MinerTemplate memory template = minerTemplates[data.minerIndex];

        if (!template.exists) revert MinerTemplateNotSet();

        bool isMiner = data.hashrate > 0;
        string memory itemType = isMiner ? "Miner" : "Item";

        uint8 rarity = _deriveRarity(data.hashrate, template.baseHashrate);

        string memory imageRenderData = _generateTokenImage(rarityBackgrounds[rarity], template.imageData);

        // Build the name: "<MINER_NAME> #<MINER_ID>-<HASH_RATE>"
        string memory name = string(abi.encodePacked(
        template.name,
        " #",
        Strings.toString(data.minerId),
        "-",
        Strings.toString(data.hashrate)
        ));

        // Build the description
        string memory description = _generateDescription(template.name, itemType, isMiner, data.hashrate, data.powerConsumption);

        // Build attributes array
        string memory attributes = _generateAttributes(data, template.name, isMiner, rarity);

        // Build the complete JSON
        string memory json = string(abi.encodePacked(
            '{',
                '"name":"', name, '",',
                '"description":"', description, '",',
                '"image":"data:image/svg+xml;base64,',
                imageRenderData, '",',
                '"external_url":"https://miningeth.tech",',
                '"attributes":', attributes,
            '}'
        ));

        return string(abi.encodePacked(
            'data:application/json;base64,',
            Base64.encode(bytes(json))
        ));
    }

    /**
    * @dev Generate the SVG image data for a token.
    *      Backgrounds are a fixed 83x121 canvas. The miner sprite is rendered
    *      at its native pixel dimensions and auto-centered inside the canvas
    *      via a flexbox-in-foreignObject, so templates do not need to declare
    *      their sprite size. `image-rendering: pixelated` is applied to keep
    *      pixel art crisp at any display scale.
    * @param backgroundData The base64 background image data (83x121 PNG)
    * @param foregroundData The base64 miner sprite image data (any size PNG)
    * @return The base64-encoded SVG
    */
    function _generateTokenImage(
        string memory backgroundData,
        string memory foregroundData
    ) internal pure returns (string memory) {
        bytes memory completeImageData = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 83 121" shape-rendering="crispEdges" style="image-rendering:pixelated">',
            '<image href="data:image/png;base64,', backgroundData, '" x="0" y="0" width="83" height="121"/>',
            '<foreignObject x="0" y="0" width="83" height="121">',
            '<div xmlns="http://www.w3.org/1999/xhtml" style="width:100%;height:100%;display:flex;align-items:center;justify-content:center">',
            '<img src="data:image/png;base64,', foregroundData, '" style="image-rendering:pixelated;display:block"/>',
            '</div>',
            '</foreignObject>',
            '</svg>'
        );

        return Base64.encode(completeImageData);
    }

    /**
     * @dev Derive the rarity tier (100/125/150/200) from a token's final
     *      hashrate and its template's base hashrate. Mirrors the
     *      common/rare/epic/mythic multipliers applied by the Packs contract.
     *      Items (hashrate == 0) and unseeded templates default to Common.
     */
    function _deriveRarity(uint32 hashrate, uint32 baseHashrate) internal pure returns (uint8) {
        if (hashrate == 0 || baseHashrate == 0) return 100;
        uint256 mul = (uint256(hashrate) * 100) / uint256(baseHashrate);
        if (mul >= 200) return 200;
        if (mul >= 150) return 150;
        if (mul >= 125) return 125;
        return 100;
    }

    function _rarityName(uint8 rarity) internal pure returns (string memory) {
        if (rarity == 200) return "Mythic";
        if (rarity == 150) return "Epic";
        if (rarity == 125) return "Rare";
        return "Common";
    }

    /**
 * @dev Generate the description text
 */
function _generateDescription(
    string memory templateName,
    string memory itemType,
    bool isMiner,
    uint256 hashrate,
    uint256 powerConsumption
) internal pure returns (string memory) {
    string memory description = string(abi.encodePacked(
        "A ",
        templateName,
        " Meth ",
        itemType,
        ", "
    ));

    if (isMiner) {
        return string(abi.encodePacked(
            description,
            "which generates ",
            hashrate.toString(),
            " GH/s and consumes ",
            powerConsumption.toString(),
            " W."
        ));
    } else {
        return string(abi.encodePacked(
            description,
            "that really looks methed out."
        ));
    }
}

/**
 * @dev Generate the attributes JSON array
 */
function _generateAttributes(
    MinerData memory data,
    string memory templateName,
    bool isMiner,
    uint8 rarity
) internal pure returns (string memory) {
    return string(abi.encodePacked(
        '[',
            '{"trait_type":"Hash Rate","value":"', Strings.toString(data.hashrate), ' GH/s"},',
            '{"trait_type":"Power Consumption","value":"', Strings.toString(data.powerConsumption), ' W"},',
            '{"trait_type":"Name","value":"', templateName, '"},',
            '{"trait_type":"Rarity","value":"', _rarityName(rarity), '"},',
            '{"trait_type":"Miner","value":', isMiner ? 'true' : 'false', '},',
            '{"trait_type":"Miner ID","value":"', Strings.toString(data.minerId), '"}',
        ']'
    ));
}

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * @dev Get miner data for a token
     * @param tokenId The token ID to query
     * @return minerId Original miner ID from the game
     * @return minerIndex Miner type/template index
     * @return hashrate Mining power
     * @return powerConsumption Power consumption
     */
    function getMinerData(uint256 tokenId)
        external
        view
        returns (
            uint32 minerId,
            uint8 minerIndex,
            uint32 hashrate,
            uint32 powerConsumption
        )
    {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        MinerData memory data = minerData[tokenId];
        return (data.minerId, data.minerIndex, data.hashrate, data.powerConsumption);
    }

    /**
     * @dev Get miner template data
     * @param minerIndex The miner type index
     * @return name The name of the miner type
     * @return imageData The base64 encoded image data
     * @return baseHashrate The template's base hashrate (used to derive a token's rarity tier)
     * @return exists Whether the template exists
     */
    function getMinerTemplate(uint256 minerIndex)
        external
        view
        returns (
            string memory name,
            string memory imageData,
            uint32 baseHashrate,
            bool exists
        )
    {
        MinerTemplate memory template = minerTemplates[minerIndex];
        return (template.name, template.imageData, template.baseHashrate, template.exists);
    }

    /**
     * @dev Set the background image for a specific rarity tier.
     * @param rarity The rarity multiplier (100=Common, 125=Rare, 150=Epic, 200=Mythic)
     * @param imageData The base64 encoded background image data (83x121 PNG)
     */
    function setRarityBackground(uint8 rarity, string memory imageData) external onlyOwner {
        if (rarity != 100 && rarity != 125 && rarity != 150 && rarity != 200) revert InvalidRarity();
        rarityBackgrounds[rarity] = imageData;
        emit RarityBackgroundUpdated(rarity);
    }

    /**
     * @dev Batch-set rarity backgrounds. Arrays must be the same length.
     */
    function setRarityBackgroundBatch(uint8[] calldata rarities, string[] calldata imageData) external onlyOwner {
        uint256 n = rarities.length;
        if (n != imageData.length) revert InvalidMinerData();
        for (uint256 i = 0; i < n; i++) {
            uint8 r = rarities[i];
            if (r != 100 && r != 125 && r != 150 && r != 200) revert InvalidRarity();
            rarityBackgrounds[r] = imageData[i];
            emit RarityBackgroundUpdated(r);
        }
    }

    /**
     * @dev Batch add/update miner templates. All arrays must be the same length.
     */
    function setMinerTemplateBatch(
        uint8[] calldata indices,
        string[] calldata names,
        string[] calldata imageData,
        uint32[] calldata baseHashrates
    ) external onlyOwner {
        uint256 n = indices.length;
        if (n != names.length || n != imageData.length || n != baseHashrates.length) revert InvalidMinerData();
        for (uint256 i = 0; i < n; i++) {
            uint8 idx = indices[i];
            bool exists = minerTemplates[idx].exists;
            minerTemplates[idx] = MinerTemplate({
                name: names[i],
                imageData: imageData[i],
                baseHashrate: baseHashrates[i],
                exists: true
            });
            if (exists) {
                emit MinerTemplateUpdated(idx, names[i]);
            } else {
                emit MinerTemplateAdded(idx, names[i]);
            }
        }
    }

    /**
     * @dev Get all token IDs owned by an address
     * @param owner Address to query
     * @return tokenIds Array of token IDs owned by the address
     */
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);
        uint256 index = 0;

        for (uint256 tokenId = 1; tokenId <= _tokenIdCounter; tokenId++) {
            if (_ownerOf(tokenId) == owner) {
                tokens[index] = tokenId;
                index++;
            }
        }

        return tokens;
    }

    /**
     * @dev Get total number of minted tokens (including burned)
     */
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        ADMIN FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * @dev Set the mining contract address (only owner)
     * @param _miningContract Address of the mining contract
     */
    function setMiningContract(address _miningContract) external onlyOwner {
        address oldContract = miningContract;
        miningContract = _miningContract;
        emit MiningContractUpdated(oldContract, _miningContract);
    }

    /// @dev Authorize an additional minter (e.g. Packs).
    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        if (minter == address(0)) revert InvalidMinerData();
        authorizedMinters[minter] = authorized;
        emit AuthorizedMinterUpdated(minter, authorized);
    }

    // OVERRIDES
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }
}