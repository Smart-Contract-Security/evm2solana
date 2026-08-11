// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface IR3 {
    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory);
    function decodeSecret(uint256 tokenId, uint256 seed) external view returns (string memory);
}

contract BinaryPunks {
    // ── ERC721 ──────────────────────────────────────────────
    string public name   = "Binary Punks";
    string public symbol = "BPUNK";
    uint256 public totalSupply;

    mapping(uint256 => address) private _owner;
    mapping(address => uint256) private _balance;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _approvedAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ── Project ─────────────────────────────────────────────
    uint256 public constant MAX_SUPPLY      = 10000;
    uint256 public constant FREE_MAX        = 7500;
    uint256 public constant FREE_PER_WALLET = 2;
    uint256 public constant MINT_PRICE      = 0.0001 ether;
    uint256 public constant ROYALTY_BPS     = 400; // 4%

    address public owner;
    address public r3;
    uint256 public seed;
    bool    public mintOpen;

    mapping(address => uint256) public freeMinted;

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }

    constructor() {
        owner = msg.sender;
        seed  = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
    }

    // ── Admin ───────────────────────────────────────────────
    function setR3(address _r3) external onlyOwner { r3 = _r3; }
    function setMintOpen(bool _open) external onlyOwner { mintOpen = _open; }
    function withdraw() external onlyOwner {
        (bool ok,) = owner.call{value: address(this).balance}("");
        require(ok);
    }

    // ── Mint ────────────────────────────────────────────────
    function freeMint(uint256 qty) external {
        require(mintOpen,                                    "mint closed");
        require(qty > 0 && qty <= FREE_PER_WALLET,          "qty 1-2");
        require(freeMinted[msg.sender] + qty <= FREE_PER_WALLET, "free limit");
        require(totalSupply + qty <= FREE_MAX,              "free supply done");
        require(totalSupply + qty <= MAX_SUPPLY,            "sold out");
        freeMinted[msg.sender] += qty;
        for (uint256 i = 0; i < qty; i++) _mint(msg.sender, totalSupply);
    }

    function mint(uint256 qty) external payable {
        require(mintOpen,                           "mint closed");
        require(qty > 0,                            "qty > 0");
        require(totalSupply + qty <= MAX_SUPPLY,    "sold out");
        require(msg.value >= MINT_PRICE * qty,      "insufficient eth");
        for (uint256 i = 0; i < qty; i++) _mint(msg.sender, totalSupply);
    }

    function _mint(address to, uint256 tokenId) internal {
        _owner[tokenId] = to;
        _balance[to]++;
        totalSupply++;
        emit Transfer(address(0), to, tokenId);
    }

    // ── ERC721 ──────────────────────────────────────────────
    function ownerOf(uint256 tokenId) public view returns (address) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return _owner[tokenId];
    }
    function balanceOf(address addr) public view returns (uint256) {
        require(addr != address(0));
        return _balance[addr];
    }
    function approve(address to, uint256 tokenId) external {
        require(msg.sender == ownerOf(tokenId) || _approvedAll[ownerOf(tokenId)][msg.sender]);
        _approved[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
    function getApproved(uint256 tokenId) public view returns (address) { return _approved[tokenId]; }
    function setApprovalForAll(address operator, bool approved) external {
        _approvedAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    function isApprovedForAll(address _own, address operator) public view returns (bool) {
        return _approvedAll[_own][operator];
    }
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApproved(msg.sender, tokenId));
        require(ownerOf(tokenId) == from);
        require(to != address(0));
        _approved[tokenId] = address(0);
        _balance[from]--;
        _balance[to]++;
        _owner[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }
    function _isApproved(address spender, uint256 tokenId) internal view returns (bool) {
        address tok_owner = ownerOf(tokenId);
        return spender == tok_owner
            || _approved[tokenId] == spender
            || _approvedAll[tok_owner][spender];
    }
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x80ac58cd || id == 0x5b5e139f || id == 0x01ffc9a7 || id == 0x2a55205a;
    }

    // ── ERC2981 Royalty ─────────────────────────────────────
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (owner, (salePrice * ROYALTY_BPS) / 10000);
    }

    // ── TokenURI ────────────────────────────────────────────
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return IR3(r3).tokenURI(tokenId, seed);
    }

    // ── Decode secret word for a token ──────────────────────
    function decodeSecret(uint256 tokenId) external view returns (string memory) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return IR3(r3).decodeSecret(tokenId, seed);
    }
}
