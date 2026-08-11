// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./SignatureRecovery.sol";

contract Kingdom is ERC721, Ownable, SignatureRecovery {
    using Strings for uint256;

    string public constant COLLECTION = "League of Kingdoms Memoir NFT";
    string public constant FAMILY = "League of Kingdoms";
    string public constant DEFAULT_DESCRIPTION =
        "Thank you for playing League of Kingdoms. We offer our deepest gratitude to those who stayed with us until the very end.";

    address public validator;
    string public description;
    string public baseImageUrl;
    uint256 public nextTokenId = 1;
    mapping(bytes12 => uint256) public kingdomTokenId;
    mapping(uint256 => bytes12) public kingdoms;
    mapping(uint256 => KingdomMetadata) public kingdomMetadata;
    event Claim(address indexed owner, bytes12 kingdom, uint256 tokenId);

    struct ClaimData {
        address receiver;//contract
        address owner;
        bytes12 kingdom;
        string name;
        string alliance;
        uint8 continent;
        uint40 power;
        uint8 lordLevel;
        uint8 castleLevel;
        string registered;
    }

    struct KingdomMetadata {
        string name;
        string alliance;
        uint8 continent;
        uint40 power;
        uint8 lordLevel;
        uint8 castleLevel;
        string registered;
    }

    constructor() ERC721(COLLECTION, "LOKM") Ownable(msg.sender) {
		setValidator(0xff97eB691606A15DD23bEE17509a7D5f566ADDc4);
        setDescription(DEFAULT_DESCRIPTION);
		setBaseImageUrl("https://lok-nft.leagueofkingdoms.com/api/card/kingdom/");
    }

    function setDescription(string memory newDescription) public onlyOwner {
        description = newDescription;
    }

    function setBaseImageUrl(string memory newBaseImageUrl) public onlyOwner {
        baseImageUrl = newBaseImageUrl;
    }

    function setValidator(address newValidator) public onlyOwner {
        validator = newValidator;
    }

    function claim(bytes calldata payload, bytes calldata signature) external {
        ClaimData memory c = abi.decode(payload, (ClaimData));
        require(c.receiver == address(this), "Invalid receiver");
        require(c.owner == msg.sender, "Invalid owner");
        require(kingdomTokenId[c.kingdom] == 0, "Kingdom already claimed");

        require(recover(keccak256(payload), signature) == validator, "Invalid signature");

        uint256 tokenId = nextTokenId++;
        kingdomTokenId[c.kingdom] = tokenId;
        kingdoms[tokenId] = c.kingdom;
        kingdomMetadata[tokenId] = KingdomMetadata({
            name: c.name,
            alliance: c.alliance,
            continent: c.continent,
            power: c.power,
            lordLevel: c.lordLevel,
            castleLevel: c.castleLevel,
            registered: c.registered
        });
        _safeMint(c.owner, tokenId);
        emit Claim(c.owner, c.kingdom, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        KingdomMetadata memory metadata = kingdomMetadata[tokenId];
        string memory imageUrl = string.concat(baseImageUrl, tokenId.toString());
        string memory attributes = string.concat(
            _attributeString("Name", metadata.name),
            ",",
            _attributeString("Alliance", metadata.alliance),
            ",",
            _attributeUint("Continent", metadata.continent),
            ",",
            _attributeUint("Power", metadata.power),
            ",",
            _attributeUint("Lord level", metadata.lordLevel),
            ",",
            _attributeUint("Castle level", metadata.castleLevel),
            ",",
            _attributeString("Registered", metadata.registered)
        );
        string memory json = string.concat(
            "{",
            _jsonProperty("name", COLLECTION),
            ",",
            _jsonProperty("description", description),
            ",",
            _jsonProperty("image", imageUrl),
            ",",
            _jsonProperty("image_url", imageUrl),
            ",\"collection\":{",
            _jsonProperty("name", COLLECTION),
            ",",
            _jsonProperty("family", FAMILY),
            "},\"attributes\":[",
            attributes,
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _attributeString(string memory trait, string memory value) private pure returns (string memory) {
        return string.concat("{", _jsonProperty("trait_type", trait), ",", _jsonProperty("value", value), "}");
    }

    function _attributeUint(string memory trait, uint256 value) private pure returns (string memory) {
        return string.concat("{", _jsonProperty("trait_type", trait), ",\"value\":", value.toString(), "}");
    }

    function _jsonProperty(string memory key, string memory value) private pure returns (string memory) {
        return string.concat("\"", key, "\":\"", _jsonEscape(value), "\"");
    }

    function _jsonEscape(string memory value) private pure returns (string memory) {
        bytes memory input = bytes(value);
        bytes memory output;
        for (uint256 i = 0; i < input.length; i++) {
            bytes1 char = input[i];
            if (char == 0x22) {
                output = abi.encodePacked(output, "\\\"");
            } else if (char == 0x5c) {
                output = abi.encodePacked(output, "\\\\");
            } else if (char == 0x0a) {
                output = abi.encodePacked(output, "\\n");
            } else if (char == 0x0d) {
                output = abi.encodePacked(output, "\\r");
            } else if (char == 0x09) {
                output = abi.encodePacked(output, "\\t");
            } else {
                output = abi.encodePacked(output, char);
            }
        }
        return string(output);
    }
}