// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title Herbarium — on-chain botanical specimens
/// @notice 10 000 pressed plants preserved on Ethereum
contract Herbarium is ERC721, ERC721Enumerable, ERC721Royalty, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    uint256 public constant COLLECTION_SIZE = 10_000;
    uint256 public constant WALLET_CAP = 20;
    uint8   public constant GRADE_MIN = 1;
    uint8   public constant GRADE_MAX = 10;
    uint256 public constant GIFT_CAP = 500;

    mapping(uint256 => uint256) public specimen;       // tokenId → seed
    mapping(uint256 => uint8)   private specimenGrade;
    mapping(uint256 => bytes32) public imprint;        // tokenId → fingerprint
    mapping(bytes32 => bool)    public imprintUsed;
    mapping(bytes32 => bool)    public consumed;       // nonces
    mapping(address => uint256) public claimed;
    mapping(address => bool)    public freeClaimed;   // tracks if address already used grade 1 gift

    uint256[10] public pricing;
    uint256 public giftsClaimed;
    address public authority;
    bool    public live;
    string  private _uri;

    constructor(
        address _authority,
        string memory baseURI_,
        address royaltyTo,
        uint96 royaltyBps
    ) ERC721("Herbarium", "HERB") Ownable(msg.sender) {
        authority = _authority;
        _uri = baseURI_;
        _setDefaultRoyalty(royaltyTo, royaltyBps);

        pricing[0] = 0;
        pricing[1] = 80000000000000;
        pricing[2] = 160000000000000;
        pricing[3] = 240000000000000;
        pricing[4] = 320000000000000;
        pricing[5] = 400000000000000;
        pricing[6] = 480000000000000;
        pricing[7] = 600000000000000;
        pricing[8] = 720000000000000;
        pricing[9] = 800000000000000;
    }

    /// @notice Collect a specimen
    function collect(
        uint8 grade,
        bytes32 fp,
        bytes32 nonce,
        uint256 deadline,
        bytes calldata sig
    ) external payable nonReentrant {
        require(live, "Not live");
        require(totalSupply() < COLLECTION_SIZE, "Complete");
        require(claimed[msg.sender] < WALLET_CAP, "Limit");
        require(grade >= GRADE_MIN && grade <= GRADE_MAX, "Grade");
        require(msg.value >= pricing[grade - 1], "Value");
        require(block.timestamp <= deadline, "Expired");
        require(!consumed[nonce], "Replay");
        require(!imprintUsed[fp], "Duplicate");

        if (grade == 1) {
            require(giftsClaimed < GIFT_CAP, "Gifts exhausted");
            require(!freeClaimed[msg.sender], "Gift used");
            giftsClaimed++;
            freeClaimed[msg.sender] = true;
        }

        bytes32 digest = keccak256(abi.encodePacked(
            msg.sender, grade, fp, nonce, deadline,
            block.chainid, address(this)
        ));
        require(
            digest.toEthSignedMessageHash().recover(sig) == authority,
            "Unauthorized"
        );

        uint256 id = totalSupply() + 1;
        uint256 dna = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.prevrandao,
            id,
            msg.sender,
            fp
        )));

        specimen[id] = dna;
        specimenGrade[id] = grade;
        imprint[id] = fp;
        imprintUsed[fp] = true;
        consumed[nonce] = true;
        claimed[msg.sender]++;

        _safeMint(msg.sender, id);
    }

    // --- reads ---

    function getData(uint256 id) external view
        returns (uint256 dna, bytes32 fp, address holder)
    {
        require(specimen[id] != 0, "!");
        return (specimen[id], imprint[id], ownerOf(id));
    }

    function fee(uint8 grade) external view returns (uint256) {
        require(grade >= GRADE_MIN && grade <= GRADE_MAX, "Grade");
        return pricing[grade - 1];
    }

    function minted() external view returns (uint256) {
        return totalSupply();
    }

    // --- admin ---

    function setAuthority(address a) external onlyOwner { authority = a; }
    function toggleLive(bool v) external onlyOwner { live = v; }
    function setURI(string calldata v) external onlyOwner { _uri = v; }

    function setFee(uint8 grade, uint256 price) external onlyOwner {
        require(grade >= GRADE_MIN && grade <= GRADE_MAX, "Grade");
        pricing[grade - 1] = price;
    }

    function setRoyalty(address to, uint96 bps) external onlyOwner {
        _setDefaultRoyalty(to, bps);
    }

    function sweep() external onlyOwner {
        (bool s,) = owner().call{value: address(this).balance}("");
        require(s);
    }

    // --- overrides ---

    function _baseURI() internal view override returns (string memory) { return _uri; }

    function _update(address to, uint256 id, address auth)
        internal override(ERC721, ERC721Enumerable) returns (address)
    { return super._update(to, id, auth); }

    function _increaseBalance(address a, uint128 v)
        internal override(ERC721, ERC721Enumerable)
    { super._increaseBalance(a, v); }

    function tokenURI(uint256 id) public view override(ERC721) returns (string memory) {
        _requireOwned(id);
        string memory b = _baseURI();
        return bytes(b).length > 0 ? string.concat(b, _str(id)) : "";
    }

    function supportsInterface(bytes4 iid)
        public view override(ERC721, ERC721Enumerable, ERC721Royalty) returns (bool)
    { return super.supportsInterface(iid); }

    function _str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v; uint256 d;
        while (t != 0) { d++; t /= 10; }
        bytes memory buf = new bytes(d);
        while (v != 0) { d--; buf[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }
}