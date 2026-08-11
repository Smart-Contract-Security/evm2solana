// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.35;

contract GreenAcres {
    enum Phase {
        Closed,
        Guaranteed,
        FCFS,
        Extra,
        Public
    }

    uint256 public constant MAX_SUPPLY = 4_000;
    uint256 public constant INITIAL_MINT_PRICE = 0.019 ether;
    uint256 public constant INITIAL_RESERVED_SUPPLY = 2_000;
    uint256 public constant GUARANTEED_MAX_ALLOWANCE = 5;
    uint256 public constant FCFS_MAX_ALLOWANCE = 3;
    uint256 public constant EXTRA_MAX_ALLOWANCE = 3;
    uint256 public constant PUBLIC_MAX_PER_WALLET = 3;

    address public owner;
    address public signer;
    string private _tokenBaseUri;

    uint256 public mintPrice = INITIAL_MINT_PRICE;
    Phase public activePhase;
    bool public tradingOpen;
    uint256 public reservedSupply = INITIAL_RESERVED_SUPPLY;
    uint256 public reserveMinted;
    uint256 public paidMinted;

    mapping(address => mapping(Phase => uint256)) public allowlistMinted;
    mapping(address => uint256) public publicMinted;

    // ERC721 state
    string public name;
    string public symbol;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    uint256 private _totalMinted;
    uint256 private _totalBurned;

    // Royalty info (ERC2981 simplified)
    address private _royaltyReceiver;
    uint96 private _royaltyFeeNumerator;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    modifier onlyOwner() {
        require(tx.accounts.owner.key == owner, "Not owner");
        _;
    }

    constructor(
        address deployer,
        address initialSigner,
        string memory baseUri
    ) {
        require(deployer != address(0) && initialSigner != address(0), "Invalid address");
        owner = deployer;
        signer = initialSigner;
        _tokenBaseUri = baseUri;
        name = "Green Acres";
        symbol = "ACRE";
        _royaltyReceiver = deployer;
        _royaltyFeeNumerator = 590; // 5.9%
        reserveMinted = 1;
        _mint(deployer, 1);
    }

    function mintAllowlist(
        Phase phase,
        uint256 allowance,
        uint256 quantity,
        uint256 deadline,
        bytes calldata /* signature */
    ) external payable {
        require(phase != Phase.Closed && phase != Phase.Public, "Invalid phase");
        require(phase == activePhase, "Phase not active");
        require(quantity > 0, "Invalid quantity");
        require(block.timestamp <= deadline, "Deadline expired");
        require(msg.value == quantity * mintPrice, "Wrong ether amount");

        uint256 maxAllowance = _maxAllowanceForPhase(phase);
        require(allowance > 0 && allowance <= maxAllowance, "Invalid allowance");

        uint256 minted = allowlistMinted[tx.accounts.sender.key][phase];
        require(minted + quantity <= allowance, "Max allowance reached");

        _consumePaidSupply(quantity);
        allowlistMinted[tx.accounts.sender.key][phase] = minted + quantity;
        paidMinted += quantity;
        _mint(tx.accounts.sender.key, quantity);
    }

    function mintPublic(uint256 quantity) external payable {
        require(activePhase == Phase.Public, "Phase not active");
        require(quantity > 0, "Invalid quantity");
        require(msg.value == quantity * mintPrice, "Wrong ether amount");

        uint256 minted = publicMinted[tx.accounts.sender.key];
        require(minted + quantity <= PUBLIC_MAX_PER_WALLET, "Max allowance reached");

        _consumePaidSupply(quantity);
        publicMinted[tx.accounts.sender.key] = minted + quantity;
        paidMinted += quantity;
        _mint(tx.accounts.sender.key, quantity);
    }

    function batchAirdrop(
        address[] calldata recipients,
        uint256[] calldata quantities
    ) external onlyOwner {
        require(recipients.length == quantities.length, "Array length mismatch");
        require(recipients.length > 0, "Invalid quantity");

        uint256 totalQuantity;
        for (uint256 i = 0; i < recipients.length; ) {
            require(recipients[i] != address(0), "Invalid address");
            require(quantities[i] > 0, "Invalid quantity");
            totalQuantity += quantities[i];
            unchecked {
                ++i;
            }
        }

        require(reserveMinted + totalQuantity <= reservedSupply, "Max supply reached");
        require(_totalMinted + totalQuantity <= MAX_SUPPLY, "Max supply reached");

        reserveMinted += totalQuantity;
        for (uint256 i = 0; i < recipients.length; ) {
            _mint(recipients[i], quantities[i]);
            unchecked {
                ++i;
            }
        }
    }

    function enableTrading() external onlyOwner {
        require(!tradingOpen, "Trading already open");
        tradingOpen = true;
    }

    function setSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid address");
        signer = newSigner;
    }

    function setBaseURI(string calldata newBaseUri) external onlyOwner {
        _tokenBaseUri = newBaseUri;
    }

    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        require(newMintPrice > 0, "Invalid mint price");
        mintPrice = newMintPrice;
    }

    function setReservedSupply(uint256 newReservedSupply) external onlyOwner {
        require(newReservedSupply >= reserveMinted, "Invalid reserve supply");
        require(paidMinted <= MAX_SUPPLY - newReservedSupply, "Invalid reserve supply");
        reservedSupply = newReservedSupply;
    }

    function setActivePhase(Phase phase) external onlyOwner {
        activePhase = phase;
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _royaltyReceiver = receiver;
        _royaltyFeeNumerator = feeNumerator;
    }

    function withdraw() external onlyOwner {
        uint256 balance = tx.accounts.owner.key.lamports;
        tx.accounts.owner.key.transfer(balance);
    }

    function totalSupply() public view returns (uint256) {
        return _totalMinted - _totalBurned;
    }

    function _startTokenId() internal pure returns (uint256) {
        return 1;
    }

    function _baseURI() internal view returns (string memory) {
        return _tokenBaseUri;
    }

    function _maxAllowanceForPhase(Phase phase) private pure returns (uint256) {
        if (phase == Phase.Guaranteed) return GUARANTEED_MAX_ALLOWANCE;
        if (phase == Phase.FCFS) return FCFS_MAX_ALLOWANCE;
        if (phase == Phase.Extra) return EXTRA_MAX_ALLOWANCE;
        revert("Invalid phase");
    }

    function _consumePaidSupply(uint256 quantity) private view {
        require(paidMinted + quantity <= MAX_SUPPLY - reservedSupply, "Max supply reached");
        require(_totalMinted + quantity <= MAX_SUPPLY, "Max supply reached");
    }

    // ERC721 implementation
    function balanceOf(address owner_) public view returns (uint256) {
        require(owner_ != address(0), "Zero address");
        return _balances[owner_];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner_ = _owners[tokenId];
        require(owner_ != address(0), "Nonexistent token");
        return owner_;
    }

    function approve(address to, uint256 tokenId) public payable {
        require(tradingOpen, "Trading locked");
        address owner_ = ownerOf(tokenId);
        require(tx.accounts.sender.key == owner_ || isApprovedForAll(owner_, tx.accounts.sender.key), "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner_, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        require(tradingOpen, "Trading locked");
        require(operator != tx.accounts.sender.key, "Cannot approve self");
        _operatorApprovals[tx.accounts.sender.key][operator] = approved;
        emit ApprovalForAll(tx.accounts.sender.key, operator, approved);
    }

    function isApprovedForAll(address owner_, address operator) public view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable {
        require(_isApprovedOrOwner(tx.accounts.sender.key, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public payable {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public payable {
        require(_isApprovedOrOwner(tx.accounts.sender.key, tokenId), "Not authorized");
        _safeTransfer(from, to, tokenId, data);
    }

    function _mint(address to, uint256 quantity) internal {
        require(to != address(0), "Zero address");
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _totalMinted + _startTokenId();
            _totalMinted++;
            _owners[tokenId] = to;
            _balances[to]++;
            emit Transfer(address(0), to, tokenId);
        }
    }

    function _burn(uint256 tokenId) internal {
        address owner_ = ownerOf(tokenId);
        _beforeTokenTransfer(owner_, address(0), tokenId);
        _tokenApprovals[tokenId] = address(0);
        _balances[owner_]--;
        delete _owners[tokenId];
        _totalBurned++;
        emit Transfer(owner_, address(0), tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Incorrect owner");
        require(to != address(0), "Zero address");
        _beforeTokenTransfer(from, to, tokenId);
        _tokenApprovals[tokenId] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ || getApproved(tokenId) == spender || isApprovedForAll(owner_, spender));
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual {
        if (!tradingOpen && from != address(0) && to != address(0)) {
            revert("Trading locked");
        }
    }

    // ERC2981 royalty info
    function royaltyInfo(uint256 /* tokenId */, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        receiver = _royaltyReceiver;
        royaltyAmount = (salePrice * _royaltyFeeNumerator) / 10000;
    }

    // ERC721 metadata
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        string memory base = _baseURI();
        return string(abi.encodePacked(base, _toString(tokenId)));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    receive() external payable {}
}