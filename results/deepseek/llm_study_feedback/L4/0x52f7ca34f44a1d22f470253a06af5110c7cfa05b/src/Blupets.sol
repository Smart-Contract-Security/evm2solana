// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Solang on Solana does not support importing external contracts like ERC721A.
// We inline a minimal ERC721A implementation adapted for Solana.
// Note: Solang does not support 'contract' as a type, so we use address for interfaces.

interface IBlupetsCore {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IBlupetsRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

struct TokenState {
    uint256 placeholder;
}

// Minimal ERC721A base contract for Solana
contract ERC721A {
    string private _name;
    string private _symbol;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721A: owner query for nonexistent token");
        return owner;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ERC721A: balance query for the zero address");
        return _balances[owner];
    }

    function _mint(address to, uint256 quantity) internal virtual {
        // Simplified minting logic
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId();
            _owners[tokenId] = to;
            emit Transfer(address(0), to, tokenId);
        }
        _balances[to] += quantity;
    }

    function _burn(uint256 tokenId, bool approvalCheck) internal virtual {
        address owner = ownerOf(tokenId);
        if (approvalCheck) {
            require(
                _isApprovedOrOwner(tx.origin, tokenId),
                "ERC721A: transfer caller is not owner nor approved"
            );
        }
        _beforeTokenTransfers(owner, address(0), tokenId, 1);
        delete _tokenApprovals[tokenId];
        _balances[owner] -= 1;
        delete _owners[tokenId];
        emit Transfer(owner, address(0), tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(tx.origin, tokenId), "ERC721A: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);
        // On Solana, we skip the onERC721Received check as it's not supported
    }

    function approve(address to, uint256 tokenId) public virtual {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721A: approval to current owner");
        require(tx.origin == owner || isApprovedForAll(owner, tx.origin), "ERC721A: approve caller is not owner nor approved for all");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        require(operator != tx.origin, "ERC721A: approve to caller");
        _operatorApprovals[tx.origin][operator] = approved;
        emit ApprovalForAll(tx.origin, operator, approved);
    }

    function getApproved(uint256 tokenId) public view virtual returns (address) {
        require(_owners[tokenId] != address(0), "ERC721A: approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ownerOf(tokenId) == from, "ERC721A: transfer of token that is not own");
        require(to != address(0), "ERC721A: transfer to the zero address");
        _beforeTokenTransfers(from, to, tokenId, 1);
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _beforeTokenTransfers(address from, address to, uint256 startTokenId, uint256 quantity) internal virtual {}

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f;
    }

    uint256 private _currentIndex;

    function _nextTokenId() internal view returns (uint256) {
        return _currentIndex;
    }

    function _setNextTokenId(uint256 tokenId) internal {
        _currentIndex = tokenId;
    }
}

contract Blupets is ERC721A, IBlupetsCore {
    uint256 public constant BLUPETS_MAX_SUPPLY = 8192;
    bytes4 internal constant ERC4906_INTERFACE_ID = 0x49064906;
    uint256 public constant MAX_BATCH_TRANSFER = 50;

    address public renderer;

    mapping(uint256 => TokenState) private _states;
    mapping(address => bool) public isEngine;
    mapping(address => bool) public metadataUpdaters;
    mapping(uint256 => bool) public isTokenLocked;
    mapping(uint256 => address) public tokenLockEngine;
    mapping(uint256 => bool) private _engineBurning;

    address private _owner;
    uint256 internal _maxSupply;

    event EngineUpdated(address indexed engine, bool allowed);
    event RendererUpdated(address indexed renderer);
    event MetadataUpdaterUpdated(address indexed updater, bool allowed);
    event MetadataUpdate(uint256 indexed tokenId);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    error NotEngine();
    error NotMetadataUpdater();
    error TokenLocked();
    error RendererMissing();
    error InvalidRenderer();
    error InvalidOwner();
    error InvalidMetadataRange();
    error InvalidCollectionMetadata();
    error InvalidBatchTransferSize();
    error InvalidLockOwner();

    modifier onlyOwner() {
        require(tx.origin == _owner, "Not owner");
        _;
    }

    modifier onlyEngine() {
        require(isEngine[tx.origin], "Not engine");
        _;
    }

    modifier onlyMetadataUpdater() {
        require(
            isEngine[tx.origin] || metadataUpdaters[tx.origin] || tx.origin == _owner,
            "Not metadata updater"
        );
        _;
    }

    constructor(string memory name_, string memory symbol_, address admin, address renderer_, address[] memory allowedSeaDrop)
        ERC721A(name_, symbol_)
    {
        require(bytes(name_).length > 0 && bytes(symbol_).length > 0, "Invalid collection metadata");
        require(admin != address(0), "Invalid owner");
        _owner = admin;
        _maxSupply = BLUPETS_MAX_SUPPLY;
        _setRenderer(renderer_);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function tokenState(uint256 tokenId) external view returns (TokenState memory) {
        ownerOf(tokenId);
        return _states[tokenId];
    }

    function ownerOf(uint256 tokenId) public view override(ERC721A, IBlupetsCore) returns (address) {
        return ERC721A.ownerOf(tokenId);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        ownerOf(tokenId);
        require(renderer != address(0), "Renderer missing");
        return IBlupetsRenderer(renderer).tokenURI(tokenId);
    }

    function setEngine(address engine, bool allowed) external onlyOwner {
        isEngine[engine] = allowed;
        emit EngineUpdated(engine, allowed);
    }

    function setRenderer(address renderer_) external onlyOwner {
        _setRenderer(renderer_);
        emit BatchMetadataUpdate(1, BLUPETS_MAX_SUPPLY);
    }

    function setMetadataUpdater(address updater, bool allowed) external onlyOwner {
        metadataUpdaters[updater] = allowed;
        emit MetadataUpdaterUpdated(updater, allowed);
    }

    function lockToken(uint256 tokenId) external onlyEngine {
        ownerOf(tokenId);
        require(tokenLockEngine[tokenId] == address(0), "Token locked");
        isTokenLocked[tokenId] = true;
        tokenLockEngine[tokenId] = tx.origin;
    }

    function unlockToken(uint256 tokenId) external onlyEngine {
        ownerOf(tokenId);
        require(tokenLockEngine[tokenId] == tx.origin, "Invalid lock owner");
        isTokenLocked[tokenId] = false;
        delete tokenLockEngine[tokenId];
    }

    function evolve(uint256 tokenId, TokenState calldata nextState) external onlyEngine {
        ownerOf(tokenId);
        require(tokenLockEngine[tokenId] == tx.origin, "Invalid lock owner");
        _states[tokenId] = nextState;
        isTokenLocked[tokenId] = false;
        delete tokenLockEngine[tokenId];
        emit MetadataUpdate(tokenId);
    }

    function burnForMerge(uint256 tokenId) external onlyEngine {
        ownerOf(tokenId);
        require(tokenLockEngine[tokenId] == tx.origin, "Invalid lock owner");
        _engineBurning[tokenId] = true;
        _burn(tokenId, false);
        _engineBurning[tokenId] = false;
        delete isTokenLocked[tokenId];
        delete tokenLockEngine[tokenId];
        delete _states[tokenId];
    }

    function notifyMetadataUpdate(uint256 tokenId) external onlyMetadataUpdater {
        ownerOf(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function notifyBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyMetadataUpdater {
        require(fromTokenId > 0 && fromTokenId <= toTokenId && toTokenId <= BLUPETS_MAX_SUPPLY, "Invalid metadata range");
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function batchTransferFrom(address from, address to, uint256[] calldata tokenIds) external {
        uint256 count = tokenIds.length;
        require(count > 0 && count <= MAX_BATCH_TRANSFER, "Invalid batch transfer size");

        for (uint256 i = 0; i < count; i++) {
            transferFrom(from, to, tokenIds[i]);
        }
    }

    function safeBatchTransferFrom(address from, address to, uint256[] calldata tokenIds) external {
        safeBatchTransferFrom(from, to, tokenIds, "");
    }

    function safeBatchTransferFrom(address from, address to, uint256[] calldata tokenIds, bytes memory data) public {
        uint256 count = tokenIds.length;
        require(count > 0 && count <= MAX_BATCH_TRANSFER, "Invalid batch transfer size");

        for (uint256 i = 0; i < count; i++) {
            safeTransferFrom(from, to, tokenIds[i], data);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || ERC721A.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfers(address from, address to, uint256 startTokenId, uint256 quantity) internal override {
        ERC721A._beforeTokenTransfers(from, to, startTokenId, quantity);
        if (from == address(0)) return;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = startTokenId + i;
            require(!(isTokenLocked[tokenId] && !_engineBurning[tokenId]), "Token locked");
        }
    }

    function _setRenderer(address renderer_) internal {
        require(renderer_ != address(0), "Invalid renderer");
        renderer = renderer_;
        emit RendererUpdated(renderer_);
    }
}