// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

struct NoisieTraits {
    uint8 gender; uint8 skinIdx; uint8 hairCI; uint8 faceShape;
    uint8 hairStyle; uint8 browStyle; uint8 eyeStyle; uint8 eyeSize;
    uint8 noseStyle; uint8 lipStyle; uint8 lipFull; uint8 expr;
    uint8 acc; uint8 glasses; uint8 beard; uint8 makeup;
    uint8 freckles; uint8 age; uint8 mole; uint8 scar;
    uint8 dimples; uint8 chinShape;
}

interface IR4 {
    function tokenURI(uint256 tokenId, uint256 seed) external view returns (string memory);
    function decodeTraits(uint256 tokenId, uint256 seed) external pure returns (NoisieTraits memory);
}

interface IStaking {
    function isSoulbound(uint256 tokenId) external view returns (bool);
}

contract Noisies {
    // ── ERC721 STATE ──────────────────────────────────────
    string public constant name   = "Noisies";
    string public constant symbol = "NOISIE";

    mapping(uint256 => address) private _owner;
    mapping(address => uint256) private _balance;
    mapping(uint256 => address) private _approved;
    mapping(address => mapping(address => bool)) private _approvedAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ── NOISIES STATE ─────────────────────────────────────
    address public contractOwner;
    address public r4;
    address public staking;
    address public collaborator;

    uint256 public constant MAX_SUPPLY        = 10000;
    uint256 public constant FREE_MAX          = 9700;
    uint256 public constant PAID_MAX          = 300;
    uint256 public constant RESERVE_MAX       = 150;
    uint256 public constant FREE_PER_WALLET   = 3;
    uint256 public constant MINT_PRICE        = 0.0001 ether;
    uint256 public constant ROYALTY_BPS       = 500; // 5%

    uint256 public totalSupply;
    uint256 public freeMintedTotal;
    uint256 public paidMintedTotal;
    uint256 public reserveMinted;
    uint256 public seed;

    bool public mintOpen;
    bool public whitelistOpen;
    bool public paused;

    mapping(address => uint256) public freeMinted;
    mapping(address => bool)    public whitelist;

    event MintOpened(bool open);
    event Withdrawn(address to, uint256 amount);

    modifier onlyOwner() { require(msg.sender == contractOwner, "not owner"); _; }
    modifier onlyOwnerOrCollab() { require(msg.sender == contractOwner || msg.sender == collaborator, "not authorized"); _; }
    modifier whenNotPaused() { require(!paused, "paused"); _; }

    constructor() {
        contractOwner = msg.sender;
        seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
    }

    // ── ADMIN ─────────────────────────────────────────────
    function setR4(address _r4) external onlyOwner { r4 = _r4; }
    function setStaking(address _staking) external onlyOwner { staking = _staking; }
    function setMintOpen(bool _open) external onlyOwner { mintOpen = _open; emit MintOpened(_open); }
    function setWhitelistOpen(bool _open) external onlyOwner { whitelistOpen = _open; }
    function setCollaborator(address col) external onlyOwner { collaborator = col; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function setWhitelist(address[] calldata addrs, bool status) external onlyOwnerOrCollab {
        for (uint256 i = 0; i < addrs.length; i++) whitelist[addrs[i]] = status;
    }

    // ── MINT ──────────────────────────────────────────────
    function freeMint(uint256 qty) external whenNotPaused {
        require(mintOpen, "mint closed");
        if (whitelistOpen) require(whitelist[msg.sender], "not whitelisted");
        require(qty > 0 && qty <= FREE_PER_WALLET, "invalid qty");
        require(freeMinted[msg.sender] + qty <= FREE_PER_WALLET, "exceeds wallet limit");
        require(freeMintedTotal + qty <= FREE_MAX, "free supply done");
        require(totalSupply + qty <= MAX_SUPPLY, "sold out");
        freeMinted[msg.sender] += qty;
        freeMintedTotal += qty;
        for (uint256 i = 0; i < qty; i++) _mint(msg.sender, totalSupply);
    }

    function mint(uint256 qty) external payable whenNotPaused {
        require(mintOpen, "mint closed");
        require(qty > 0 && qty <= 20, "invalid qty");
        require(msg.value >= MINT_PRICE * qty, "insufficient eth");
        require(paidMintedTotal + qty <= PAID_MAX, "paid supply done");
        require(totalSupply + qty <= MAX_SUPPLY, "sold out");
        paidMintedTotal += qty;
        for (uint256 i = 0; i < qty; i++) _mint(msg.sender, totalSupply);
    }

    function ownerMint(uint256 qty, address to) external onlyOwnerOrCollab {
        require(qty > 0, "invalid qty");
        require(reserveMinted + qty <= RESERVE_MAX, "reserve done");
        require(freeMintedTotal + qty <= FREE_MAX, "free supply done");
        require(totalSupply + qty <= MAX_SUPPLY, "sold out");
        reserveMinted += qty;
        freeMintedTotal += qty;
        for (uint256 i = 0; i < qty; i++) _mint(to, totalSupply);
    }

    function _mint(address to, uint256 tokenId) internal {
        _owner[tokenId] = to;
        _balance[to]++;
        totalSupply++;
        emit Transfer(address(0), to, tokenId);
    }

    // ── BURN ──────────────────────────────────────────────
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "not owner");
        _owner[tokenId] = address(0);
        _balance[msg.sender]--;
        emit Transfer(msg.sender, address(0), tokenId);
    }

    function burnToUpgrade(uint256 burnId, uint256 keepId) external {
        require(ownerOf(burnId) == msg.sender, "not owner of burn");
        require(ownerOf(keepId) == msg.sender, "not owner of keep");
        _owner[burnId] = address(0);
        _balance[msg.sender]--;
        emit Transfer(msg.sender, address(0), burnId);
        // Grant bonus points to keepId via staking contract (if connected)
        // This is handled off-chain or via staking contract integration
    }

    // ── AIRDROP / SNAPSHOT ────────────────────────────────
    function airdrop(address[] calldata to, uint256 qty) external onlyOwnerOrCollab {
        for (uint256 i = 0; i < to.length; i++) {
            require(totalSupply + qty <= MAX_SUPPLY, "sold out");
            for (uint256 j = 0; j < qty; j++) _mint(to[i], totalSupply);
        }
    }

    function snapshot() external view onlyOwner returns (address[] memory holders, uint256[] memory ids) {
        holders = new address[](totalSupply);
        ids     = new uint256[](totalSupply);
        for (uint256 i = 0; i < totalSupply; i++) {
            holders[i] = _owner[i];
            ids[i] = i;
        }
    }

    // ── ERC721 ────────────────────────────────────────────
    function ownerOf(uint256 tokenId) public view returns (address) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return _owner[tokenId];
    }

    function balanceOf(address addr) public view returns (uint256) {
        require(addr != address(0), "zero address");
        return _balance[addr];
    }

    function approve(address to, uint256 tokenId) external {
        address tok_owner = ownerOf(tokenId);
        require(msg.sender == tok_owner || _approvedAll[tok_owner][msg.sender], "not authorized");
        _approved[tokenId] = to;
        emit Approval(tok_owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return _approved[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _approvedAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner2, address operator) public view returns (bool) {
        return _approvedAll[owner2][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public whenNotPaused {
        require(_isApproved(msg.sender, tokenId), "not authorized");
        require(ownerOf(tokenId) == from, "wrong from");
        require(to != address(0), "zero address");
        if (staking != address(0)) require(!IStaking(staking).isSoulbound(tokenId), "soulbound");
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
        return spender == tok_owner || _approved[tokenId] == spender || _approvedAll[tok_owner][spender];
    }

    // ── METADATA ──────────────────────────────────────────
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return IR4(r4).tokenURI(tokenId, seed);
    }

    function traitDetails(uint256 tokenId) external view returns (NoisieTraits memory) {
        require(_owner[tokenId] != address(0), "nonexistent");
        return IR4(r4).decodeTraits(tokenId, seed);
    }

    // ── ERC2981 ROYALTY ───────────────────────────────────
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (contractOwner, (salePrice * ROYALTY_BPS) / 10000);
    }

    function setRoyalty(uint256) external onlyOwner {
        // royalty is fixed at 5% — intentionally not changeable
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f // ERC721Metadata
            || interfaceId == 0x2a55205a // ERC2981
            || interfaceId == 0x01ffc9a7; // ERC165
    }

    // ── WITHDRAW ──────────────────────────────────────────
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "nothing to withdraw");
        (bool ok,) = contractOwner.call{value: bal}("");
        require(ok, "transfer failed");
        emit Withdrawn(contractOwner, bal);
    }

    receive() external payable {}
}
