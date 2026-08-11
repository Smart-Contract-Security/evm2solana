import 'solana';

contract WCLPunkMint {
    uint64 private _nextTokenId;
    uint64 public mintPrice = 150000000000000; // 0.00015 SOL in lamports
    uint64 public maxSupply = 3200;
    mapping(address => uint64) public mintedPerWallet;
    uint64 public maxPerWallet = 3;

    address private _owner;
    string private _name;
    string private _symbol;

    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint64 => string) private _tokenURIs;
    mapping(address => mapping(uint64 => uint64)) private _ownedTokens;
    mapping(uint64 => uint64) private _ownedTokensIndex;
    uint64[] private _allTokens;
    mapping(uint64 => uint64) private _allTokensIndex;

    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    constructor() {
        _name = "WCL Punk Mint";
        _symbol = "PUNK";
        _owner = tx.accounts.dataAccount.key;
    }

    function mint(string memory uri) external {
        require(_nextTokenId < maxSupply, "Sold out");
        require(mintedPerWallet[tx.accounts.dataAccount.key] < maxPerWallet, "Max 3 per wallet");

        uint64 tokenId = _nextTokenId;
        _nextTokenId++;

        _mint(tx.accounts.dataAccount.key, tokenId);
        _setTokenURI(tokenId, uri);
        mintedPerWallet[tx.accounts.dataAccount.key]++;
    }

    function totalMinted() external view returns (uint64) {
        return _nextTokenId;
    }

    function withdraw() external onlyOwner {
        // Transfer lamports from data account to owner
        // Solana requires explicit account handling for SOL transfers
        // This is a simplified version - actual implementation would need proper account passing
    }

    function balanceOf(address owner) public view returns (uint64) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function ownerOf(uint64 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Invalid token");
        return owner;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint64 tokenId) public view returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function approve(address to, uint64 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "Self approval");
        require(tx.accounts.dataAccount.key == owner || isApprovedForAll(owner, tx.accounts.dataAccount.key), "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint64 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Invalid token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        require(operator != tx.accounts.dataAccount.key, "Self approval");
        _operatorApprovals[tx.accounts.dataAccount.key][operator] = approved;
        emit ApprovalForAll(tx.accounts.dataAccount.key, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint64 tokenId) public {
        require(_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint64 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint64 tokenId, bytes memory data) public {
        require(_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId), "Not authorized");
        _safeTransfer(from, to, tokenId, data);
    }

    function totalSupply() public view returns (uint64) {
        return uint64(_allTokens.length);
    }

    function tokenByIndex(uint64 index) public view returns (uint64) {
        require(index < totalSupply(), "Index out of bounds");
        return _allTokens[index];
    }

    function tokenOfOwnerByIndex(address owner, uint64 index) public view returns (uint64) {
        require(index < balanceOf(owner), "Index out of bounds");
        return _ownedTokens[owner][index];
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f || // ERC721Metadata
            interfaceId == 0x780e9d63;   // ERC721Enumerable
    }

    function _mint(address to, uint64 tokenId) internal {
        require(to != address(0), "Zero address");
        require(_owners[tokenId] == address(0), "Already minted");

        _balances[to]++;
        _owners[tokenId] = to;

        _addTokenToAllTokensEnumeration(tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(address(0), to, tokenId);
    }

    function _burn(uint64 tokenId) internal {
        address owner = ownerOf(tokenId);

        _clearApproval(tokenId);
        _balances[owner]--;
        delete _owners[tokenId];
        delete _tokenURIs[tokenId];

        _removeTokenFromOwnerEnumeration(owner, tokenId);
        _removeTokenFromAllTokensEnumeration(tokenId);

        emit Transfer(owner, address(0), tokenId);
    }

    function _transfer(address from, address to, uint64 tokenId) internal {
        require(ownerOf(tokenId) == from, "Not owner");
        require(to != address(0), "Zero address");

        _clearApproval(tokenId);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(address from, address to, uint64 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
    }

    function _setTokenURI(uint64 tokenId, string memory uri) internal {
        require(_owners[tokenId] != address(0), "Invalid token");
        _tokenURIs[tokenId] = uri;
    }

    function _isApprovedOrOwner(address spender, uint64 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _clearApproval(uint64 tokenId) internal {
        if (_tokenApprovals[tokenId] != address(0)) {
            delete _tokenApprovals[tokenId];
        }
    }

    function _addTokenToAllTokensEnumeration(uint64 tokenId) internal {
        _allTokensIndex[tokenId] = uint64(_allTokens.length);
        _allTokens.push(tokenId);
    }

    function _addTokenToOwnerEnumeration(address to, uint64 tokenId) internal {
        uint64 length = balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint64 tokenId) internal {
        uint64 lastTokenIndex = balanceOf(from) - 1;
        uint64 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint64 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokens[from][lastTokenIndex];
        delete _ownedTokensIndex[tokenId];
    }

    function _removeTokenFromAllTokensEnumeration(uint64 tokenId) internal {
        uint64 lastTokenIndex = uint64(_allTokens.length) - 1;
        uint64 tokenIndex = _allTokensIndex[tokenId];

        uint64 lastTokenId = _allTokens[lastTokenIndex];
        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        _allTokens.pop();
        delete _allTokensIndex[tokenId];
    }
}