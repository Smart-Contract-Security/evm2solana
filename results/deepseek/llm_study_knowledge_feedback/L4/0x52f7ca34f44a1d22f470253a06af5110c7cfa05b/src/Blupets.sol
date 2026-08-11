// SPDX-License-Identifier: MIT

import {IBlupetsRenderer} from "./IBlupetsRenderer.sol";

struct TokenState {
    uint64 level;
    uint64 experience;
    bytes data;
}

contract Blupets {
    uint64 public constant BLUPETS_MAX_SUPPLY = 8192;
    bytes4 internal constant ERC4906_INTERFACE_ID = 0x49064906;
    uint64 public constant MAX_BATCH_TRANSFER = 50;

    address public renderer;

    mapping(uint64 => TokenState) private _states;
    mapping(address => bool) public isEngine;
    mapping(address => bool) public metadataUpdaters;
    mapping(uint64 => bool) public isTokenLocked;
    mapping(uint64 => address) public tokenLockEngine;
    mapping(uint64 => bool) private _engineBurning;

    string private _name;
    string private _symbol;
    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    uint64 private _currentIndex;
    uint64 private _burnCounter;
    uint64 internal _maxSupply;
    address private _owner;

    address[] private _allowedSeaDrop;

    event EngineUpdated(address indexed engine, bool allowed);
    event RendererUpdated(address indexed renderer);
    event MetadataUpdaterUpdated(address indexed updater, bool allowed);
    event MetadataUpdate(uint64 indexed tokenId);
    event BatchMetadataUpdate(uint64 fromTokenId, uint64 toTokenId);
    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SeaDropAllowed(address indexed allowedSeaDrop);

    constructor(string memory name_, string memory symbol_, address admin, address renderer_, address[] memory allowedSeaDrop) {
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) {
            revert("InvalidCollectionMetadata");
        }
        if (admin == address(0)) {
            revert("InvalidOwner");
        }
        _name = name_;
        _symbol = symbol_;
        _owner = admin;
        _currentIndex = _startTokenId();
        _maxSupply = BLUPETS_MAX_SUPPLY;
        _allowedSeaDrop = allowedSeaDrop;
        _setRenderer(renderer_);
        emit OwnershipTransferred(address(0), admin);
    }

    function _startTokenId() internal pure returns (uint64) {
        return 1;
    }

    modifier onlyOwner() {
        if (tx.accounts.dataAccount.key != _owner) {
            revert("NotOwner");
        }
        _;
    }

    modifier onlyEngine() {
        if (!isEngine[tx.accounts.dataAccount.key]) {
            revert("NotEngine");
        }
        _;
    }

    modifier onlyMetadataUpdater() {
        if (!isEngine[tx.accounts.dataAccount.key] && !metadataUpdaters[tx.accounts.dataAccount.key] && tx.accounts.dataAccount.key != _owner) {
            revert("NotMetadataUpdater");
        }
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) {
            revert("InvalidOwner");
        }
        address previousOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function totalSupply() public view returns (uint64) {
        return _currentIndex - _startTokenId() - _burnCounter;
    }

    function balanceOf(address owner_) public view returns (uint64) {
        if (owner_ == address(0)) {
            revert("BalanceQueryForZeroAddress");
        }
        return _balances[owner_];
    }

    function ownerOf(uint64 tokenId) public view returns (address) {
        address owner_ = _owners[tokenId];
        if (owner_ == address(0)) {
            revert("OwnerQueryForNonexistentToken");
        }
        return owner_;
    }

    function tokenState(uint64 tokenId) external view returns (TokenState memory) {
        ownerOf(tokenId);
        return _states[tokenId];
    }

    function tokenURI(uint64 tokenId) public view returns (string memory) {
        ownerOf(tokenId);
        if (renderer == address(0)) {
            revert("RendererMissing");
        }
        (bool success, bytes memory result) = renderer.call(abi.encodeWithSignature("tokenURI(uint64)", tokenId));
        if (!success) {
            revert("RendererCallFailed");
        }
        return abi.decode(result, (string));
    }

    function approve(address to, uint64 tokenId) public {
        address owner_ = ownerOf(tokenId);
        if (to == owner_) {
            revert("ApprovalToCurrentOwner");
        }
        if (tx.accounts.dataAccount.key != owner_ && !isApprovedForAll(owner_, tx.accounts.dataAccount.key)) {
            revert("NotApprovedOrOwner");
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner_, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        address owner_ = tx.accounts.dataAccount.key;
        if (operator == owner_) {
            revert("ApprovalToCurrentOwner");
        }
        _operatorApprovals[owner_][operator] = approved;
        emit ApprovalForAll(owner_, operator, approved);
    }

    function getApproved(uint64 tokenId) public view returns (address) {
        if (!_exists(tokenId)) {
            revert("ApprovalQueryForNonexistentToken");
        }
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner_, address operator) public view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function _exists(uint64 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function transferFrom(address from, address to, uint64 tokenId) public {
        if (!_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId)) {
            revert("NotApprovedOrOwner");
        }
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint64 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint64 tokenId, bytes memory data) public {
        if (!_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId)) {
            revert("NotApprovedOrOwner");
        }
        _safeTransfer(from, to, tokenId, data);
    }

    function _isApprovedOrOwner(address spender, uint64 tokenId) internal view returns (bool) {
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ || isApprovedForAll(owner_, spender) || getApproved(tokenId) == spender);
    }

    function _safeTransfer(address from, address to, uint64 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint64 tokenId) internal {
        if (ownerOf(tokenId) != from) {
            revert("TransferFromIncorrectOwner");
        }
        if (to == address(0)) {
            revert("TransferToZeroAddress");
        }

        _beforeTokenTransfers(from, to, tokenId, 1);

        delete _tokenApprovals[tokenId];

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint64 quantity) internal {
        if (to == address(0)) {
            revert("MintToZeroAddress");
        }
        if (quantity == 0) {
            revert("MintZeroQuantity");
        }

        _beforeTokenTransfers(address(0), to, _currentIndex, quantity);

        uint64 startTokenId = _currentIndex;
        if (startTokenId + quantity > _maxSupply) {
            revert("MaxSupplyExceeded");
        }

        for (uint64 i = 0; i < quantity; i++) {
            uint64 tokenId = startTokenId + i;
            if (_owners[tokenId] != address(0)) {
                revert("TokenAlreadyMinted");
            }
            _owners[tokenId] = to;
            emit Transfer(address(0), to, tokenId);
        }

        _balances[to] += quantity;
        _currentIndex = startTokenId + quantity;
    }

    function _burn(uint64 tokenId, bool approvalCheck) internal {
        address owner_ = ownerOf(tokenId);

        if (approvalCheck) {
            if (!_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId)) {
                revert("NotApprovedOrOwner");
            }
        }

        _beforeTokenTransfers(owner_, address(0), tokenId, 1);

        delete _tokenApprovals[tokenId];

        _balances[owner_] -= 1;
        delete _owners[tokenId];
        _burnCounter += 1;

        emit Transfer(owner_, address(0), tokenId);
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

    function lockToken(uint64 tokenId) external onlyEngine {
        ownerOf(tokenId);
        if (tokenLockEngine[tokenId] != address(0)) {
            revert("TokenLocked");
        }
        isTokenLocked[tokenId] = true;
        tokenLockEngine[tokenId] = tx.accounts.dataAccount.key;
    }

    function unlockToken(uint64 tokenId) external onlyEngine {
        ownerOf(tokenId);
        if (tokenLockEngine[tokenId] != tx.accounts.dataAccount.key) {
            revert("InvalidLockOwner");
        }
        isTokenLocked[tokenId] = false;
        delete tokenLockEngine[tokenId];
    }

    function evolve(uint64 tokenId, TokenState calldata nextState) external onlyEngine {
        ownerOf(tokenId);
        if (tokenLockEngine[tokenId] != tx.accounts.dataAccount.key) {
            revert("InvalidLockOwner");
        }
        _states[tokenId] = nextState;
        isTokenLocked[tokenId] = false;
        delete tokenLockEngine[tokenId];
        emit MetadataUpdate(tokenId);
    }

    function burnForMerge(uint64 tokenId) external onlyEngine {
        ownerOf(tokenId);
        if (tokenLockEngine[tokenId] != tx.accounts.dataAccount.key) {
            revert("InvalidLockOwner");
        }
        _engineBurning[tokenId] = true;
        _burn(tokenId, false);
        _engineBurning[tokenId] = false;
        delete isTokenLocked[tokenId];
        delete tokenLockEngine[tokenId];
        delete _states[tokenId];
    }

    function notifyMetadataUpdate(uint64 tokenId) external onlyMetadataUpdater {
        ownerOf(tokenId);
        emit MetadataUpdate(tokenId);
    }

    function notifyBatchMetadataUpdate(uint64 fromTokenId, uint64 toTokenId) external onlyMetadataUpdater {
        if (fromTokenId == 0 || fromTokenId > toTokenId || toTokenId > BLUPETS_MAX_SUPPLY) {
            revert("InvalidMetadataRange");
        }
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function batchTransferFrom(address from, address to, uint64[] calldata tokenIds) external {
        uint64 count = uint64(tokenIds.length);
        if (count == 0 || count > MAX_BATCH_TRANSFER) {
            revert("InvalidBatchTransferSize");
        }

        for (uint64 i = 0; i < count; i++) {
            transferFrom(from, to, tokenIds[i]);
        }
    }

    function safeBatchTransferFrom(address from, address to, uint64[] calldata tokenIds) external {
        safeBatchTransferFrom(from, to, tokenIds, "");
    }

    function safeBatchTransferFrom(address from, address to, uint64[] calldata tokenIds, bytes memory data) public {
        uint64 count = uint64(tokenIds.length);
        if (count == 0 || count > MAX_BATCH_TRANSFER) {
            revert("InvalidBatchTransferSize");
        }

        for (uint64 i = 0; i < count; i++) {
            safeTransferFrom(from, to, tokenIds[i], data);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f || interfaceId == 0x01ffc9a7;
    }

    function _beforeTokenTransfers(address from, address to, uint64 startTokenId, uint64 quantity) internal {
        if (from == address(0)) return;

        for (uint64 i = 0; i < quantity; i++) {
            uint64 tokenId = startTokenId + i;
            if (isTokenLocked[tokenId] && !_engineBurning[tokenId]) {
                revert("TokenLocked");
            }
        }
    }

    function _setRenderer(address renderer_) internal {
        if (renderer_ == address(0)) {
            revert("InvalidRenderer");
        }
        renderer = renderer_;
        emit RendererUpdated(renderer_);
    }

    function getAllowedSeaDrop() public view returns (address[] memory) {
        return _allowedSeaDrop;
    }

    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop) external onlyOwner {
        _allowedSeaDrop = allowedSeaDrop;
        for (uint64 i = 0; i < allowedSeaDrop.length; i++) {
            emit SeaDropAllowed(allowedSeaDrop[i]);
        }
    }

    function mintSeaDrop(address minter, uint64 quantity) external {
        bool allowed = false;
        for (uint64 i = 0; i < _allowedSeaDrop.length; i++) {
            if (_allowedSeaDrop[i] == tx.accounts.dataAccount.key) {
                allowed = true;
                break;
            }
        }
        if (!allowed) {
            revert("NotApprovedOrOwner");
        }
        _mint(minter, quantity);
    }

    function getMaxSupply() public view returns (uint64) {
        return _maxSupply;
    }
}