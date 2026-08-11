// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract WorldCupCards is
    ERC721,
    Ownable,
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    struct Card { uint16 playerId; uint8 rarity; }

    uint256 public constant MAX_SUPPLY = 20_000;
    uint256 public constant PLAYERS_PER_RARITY = 741;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public nextTokenId = 1;
    uint256 public mintPrice = 0.0048 ether;
    uint256 public maxCardsPerTx = 1000;
    uint256 public maxPerAddress = 100;
    bool public allowContracts = false;

    string public baseURI;
    bytes32 public whitelistARoot;
    bytes32 public whitelistBRoot;

    mapping(uint256 => Card) public cards;
    mapping(address => bool) public wlAClaimed;
    mapping(address => bool) public wlBClaimed;
    mapping(address => uint256) public mintedCount;

    uint256[] private _burnedQueue;
    uint256 private _burnedHead;
    uint256 private _entropyNonce;

    uint256 public packs1Count;
    uint256 public packs5Count;
    uint256 public packs20Count;
    uint256 public packs50Count;

    constructor(string memory baseURI_, bytes32 wlA, bytes32 wlB)
        ERC721("WorldCupCards", "WCC")
        Ownable(msg.sender)
    {
        baseURI = baseURI_;
        whitelistARoot = wlA;
        whitelistBRoot = wlB;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 id)
        public view override(ERC721, AccessControl) returns (bool)
    {
        return super.supportsInterface(id);
    }

    function _pad4(uint256 n) internal pure returns (string memory) {
        require(n <= 9999, "out of range");
        bytes memory b = new bytes(4);
        b[3] = bytes1(uint8(48 + (n % 10)));
        b[2] = bytes1(uint8(48 + ((n / 10) % 10)));
        b[1] = bytes1(uint8(48 + ((n / 100) % 10)));
        b[0] = bytes1(uint8(48 + ((n / 1000) % 10)));
        return string(b);
    }

    function metaUri(uint256 metaIndex) public view returns (string memory) {
        return string.concat(baseURI, "/cards/meta/", _pad4(metaIndex), ".json");
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        Card memory c = cards[id];
        uint256 metaIndex = uint256(c.rarity) * PLAYERS_PER_RARITY + c.playerId;
        return metaUri(metaIndex);
    }

    function _seed(uint256 tokenId) internal returns (uint256) {
        unchecked { ++_entropyNonce; }
        return uint256(keccak256(abi.encode(
            block.prevrandao,
            block.number,
            msg.sender,
            tokenId,
            _entropyNonce
        )));
    }

    function _rollAndAssign(uint256 tokenId, bool forceLegendary) internal {
        uint256 s = _seed(tokenId);
        uint8 rarity;
        if (forceLegendary) {
            rarity = 3;
        } else {
            uint256 r = s % 10_000;
            if      (r < 5_500) rarity = 0;
            else if (r < 8_200) rarity = 1;
            else if (r < 9_600) rarity = 2;
            else                rarity = 3;
        }
        uint16 playerId = uint16((s >> 16) % PLAYERS_PER_RARITY) + 1;
        cards[tokenId] = Card(playerId, rarity);
    }

    modifier onlyEOA() {
        if (!allowContracts) {
            require(msg.sender == tx.origin, "EOA only");
            require(msg.sender.code.length == 0, "no contract");
        }
        _;
    }

    event PackMinted(
        address indexed to,
        uint256 firstId,
        uint256 count,
        bool guaranteed
    );
    event MaxCardsPerTxUpdated(uint256 v);
    event MaxPerAddressUpdated(uint256 v);
    event AllowContractsUpdated(bool v);

    function _mintPack(uint256 cardsPerPack, address to) internal {
        if      (cardsPerPack == 1)  { ++packs1Count;  }
        else if (cardsPerPack == 5)  { ++packs5Count;  }
        else if (cardsPerPack == 20) { ++packs20Count; }
        else if (cardsPerPack == 50) { ++packs50Count; }
        else revert("bad pack size");

        bool guaranteeLegendary = cardsPerPack == 50;
        uint256 firstId = nextTokenId;
        for (uint256 i = 0; i < cardsPerPack; ++i) {
            uint256 id = nextTokenId++;
            require(id <= MAX_SUPPLY, "supply cap");
            _rollAndAssign(id, guaranteeLegendary && i == 0);
            _safeMint(to, id);
        }
        emit PackMinted(to, firstId, cardsPerPack, guaranteeLegendary);
    }

    function mint(uint256 packs, uint256 cardsPerPack)
        external payable nonReentrant whenNotPaused onlyEOA
    {
        require(packs >= 1 && cardsPerPack >= 1, "zero");
        uint256 total = packs * cardsPerPack;
        require(total <= maxCardsPerTx, "tx cap");
        require(mintedCount[msg.sender] + total <= maxPerAddress, "addr cap");
        require(nextTokenId - 1 + total <= MAX_SUPPLY, "exceeds supply");
        uint256 owed = total * mintPrice;
        require(msg.value >= owed, "underpaid");
        mintedCount[msg.sender] += total;
        for (uint256 p = 0; p < packs; ++p) _mintPack(cardsPerPack, msg.sender);
        if (msg.value > owed) {
            (bool ok,) = msg.sender.call{value: msg.value - owed}("");
            require(ok, "refund failed");
        }
    }

    function setMaxCardsPerTx(uint256 v) external onlyOwner {
        maxCardsPerTx = v;
        emit MaxCardsPerTxUpdated(v);
    }
    function setMaxPerAddress(uint256 v) external onlyOwner {
        maxPerAddress = v;
        emit MaxPerAddressUpdated(v);
    }
    function setAllowContracts(bool v) external onlyOwner {
        allowContracts = v;
        emit AllowContractsUpdated(v);
    }

    event BaseURIUpdated(string v);
    event PriceUpdated(uint256 v);
    event WhitelistRootUpdated(uint8 tier, bytes32 root);
    event Withdrawn(address to, uint256 amount);

    function setBaseURI(string calldata v) external onlyOwner {
        baseURI = v;
        emit BaseURIUpdated(v);
    }
    function setMintPrice(uint256 v) external onlyOwner {
        mintPrice = v;
        emit PriceUpdated(v);
    }
    function setWhitelistARoot(bytes32 r) external onlyOwner {
        whitelistARoot = r;
        emit WhitelistRootUpdated(0, r);
    }
    function setWhitelistBRoot(bytes32 r) external onlyOwner {
        whitelistBRoot = r;
        emit WhitelistRootUpdated(1, r);
    }
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function withdraw(address payable to) external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok,) = to.call{value: bal}("");
        require(ok, "withdraw failed");
        emit Withdrawn(to, bal);
    }

    event WhitelistClaimed(address indexed who, uint8 tier, uint8 option);

    function isWhitelistedA(address who, bytes32[] calldata proof)
        external view returns (bool)
    {
        return _verifyWL(whitelistARoot, proof, who);
    }

    function isWhitelistedB(address who, bytes32[] calldata proof)
        external view returns (bool)
    {
        return _verifyWL(whitelistBRoot, proof, who);
    }

    function _verifyWL(bytes32 root, bytes32[] calldata proof, address who)
        internal pure returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(who));
        return MerkleProof.verify(proof, root, leaf);
    }

    function mintWhitelistA(bytes32[] calldata proof, uint8 option)
        external payable nonReentrant whenNotPaused onlyEOA
    {
        require(!wlAClaimed[msg.sender], "claimed");
        require(_verifyWL(whitelistARoot, proof, msg.sender), "bad proof");
        wlAClaimed[msg.sender] = true;
        if (option == 0) {
            require(msg.value == 0, "no payment");
            require(nextTokenId - 1 + 1 <= MAX_SUPPLY, "exceeds supply");
            _mintPack(1, msg.sender);
        } else if (option == 1) {
            uint256 owed = 5 * mintPrice / 2;
            require(msg.value >= owed, "underpaid");
            require(nextTokenId - 1 + 5 <= MAX_SUPPLY, "exceeds supply");
            _mintPack(5, msg.sender);
            if (msg.value > owed) {
                (bool ok,) = msg.sender.call{value: msg.value - owed}("");
                require(ok, "refund failed");
            }
        } else revert("bad option");
        emit WhitelistClaimed(msg.sender, 0, option);
    }

    function mintWhitelistB(bytes32[] calldata proof, uint8 option)
        external payable nonReentrant whenNotPaused onlyEOA
    {
        require(!wlBClaimed[msg.sender], "claimed");
        require(_verifyWL(whitelistBRoot, proof, msg.sender), "bad proof");
        wlBClaimed[msg.sender] = true;
        if (option == 0) {
            // Free claim — gives a single SINGLE pack (same as Tier A free)
            // so the FREE arm is consistent across tiers and the upgrade
            // path on B is purely a "spend half price for 20 cards" lift.
            require(msg.value == 0, "no payment");
            require(nextTokenId - 1 + 1 <= MAX_SUPPLY, "exceeds supply");
            _mintPack(1, msg.sender);
        } else if (option == 1) {
            uint256 owed = 20 * mintPrice / 2;
            require(msg.value >= owed, "underpaid");
            require(nextTokenId - 1 + 20 <= MAX_SUPPLY, "exceeds supply");
            _mintPack(20, msg.sender);
            if (msg.value > owed) {
                (bool ok,) = msg.sender.call{value: msg.value - owed}("");
                require(ok, "refund failed");
            }
        } else revert("bad option");
        emit WhitelistClaimed(msg.sender, 1, option);
    }

    event Burned(address indexed operator, uint256 tokenId);
    event Reminted(address indexed operator, address indexed to, uint256 tokenId);

    function burn(uint256[] calldata tokenIds)
        external onlyRole(OPERATOR_ROLE) whenNotPaused
    {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 id = tokenIds[i];
            address holder = ownerOf(id);
            require(_isAuthorized(holder, msg.sender, id), "not auth");
            _burn(id);
            _burnedQueue.push(id);
            emit Burned(msg.sender, id);
        }
    }

    function remint(uint256 qty, address to)
        external onlyRole(OPERATOR_ROLE) whenNotPaused
    {
        require(qty > 0 && qty <= maxCardsPerTx, "qty");
        uint256 available = _burnedQueue.length - _burnedHead;
        require(available >= qty, "queue empty");
        for (uint256 i = 0; i < qty; ++i) {
            uint256 id = _burnedQueue[_burnedHead++];
            _rollAndAssign(id, false);
            _safeMint(to, id);
            emit Reminted(msg.sender, to, id);
        }
    }

    function burnedQueueLength() external view returns (uint256) {
        return _burnedQueue.length - _burnedHead;
    }
}
