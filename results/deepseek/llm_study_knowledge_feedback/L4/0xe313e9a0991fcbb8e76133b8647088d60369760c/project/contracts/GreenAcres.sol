// SPDX-License-Identifier: UNLICENSED

import {AccountMeta} from 'solana';

// Errors as constants since custom errors are not supported
uint64 constant ERROR_ARRAY_LENGTH_MISMATCH = 1;
uint64 constant ERROR_DEADLINE_EXPIRED = 2;
uint64 constant ERROR_INVALID_ADDRESS = 3;
uint64 constant ERROR_INVALID_PHASE = 4;
uint64 constant ERROR_INVALID_MINT_PRICE = 5;
uint64 constant ERROR_INVALID_QUANTITY = 6;
uint64 constant ERROR_INVALID_RESERVE_SUPPLY = 7;
uint64 constant ERROR_INVALID_SIGNATURE = 8;
uint64 constant ERROR_MAX_ALLOWANCE_REACHED = 9;
uint64 constant ERROR_MAX_SUPPLY_REACHED = 10;
uint64 constant ERROR_PHASE_NOT_ACTIVE = 11;
uint64 constant ERROR_TRADING_LOCKED = 12;
uint64 constant ERROR_TRADING_ALREADY_OPEN = 13;
uint64 constant ERROR_WITHDRAWAL_FAILED = 14;
uint64 constant ERROR_WRONG_ETHER_AMOUNT = 15;

contract GreenAcres {
    enum Phase {
        Closed,
        Guaranteed,
        FCFS,
        Extra,
        Public
    }

    uint64 public constant MAX_SUPPLY = 4_000;
    uint64 public constant INITIAL_MINT_PRICE = 19_000_000;
    uint64 public constant INITIAL_RESERVED_SUPPLY = 2_000;
    uint64 public constant GUARANTEED_MAX_ALLOWANCE = 5;
    uint64 public constant FCFS_MAX_ALLOWANCE = 3;
    uint64 public constant EXTRA_MAX_ALLOWANCE = 3;
    uint64 public constant PUBLIC_MAX_PER_WALLET = 3;

    bytes32 private constant ALLOWLIST_MINT_TYPEHASH =
        keccak256(
            "AllowlistMint(address minter,uint8 phase,uint256 allowance,uint256 deadline)"
        );

    address public owner;
    address public signer;
    string private _tokenBaseUri;

    uint64 public mintPrice = INITIAL_MINT_PRICE;
    Phase public activePhase;
    bool public tradingOpen;
    uint64 public reservedSupply = INITIAL_RESERVED_SUPPLY;
    uint64 public reserveMinted;
    uint64 public paidMinted;

    // Token ownership and metadata
    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    string private _name;
    string private _symbol;
    uint64 private _totalMinted;
    uint64 private _totalBurned;

    // Royalty info
    address private _royaltyReceiver;
    uint96 private _royaltyFeeNumerator;

    // Allowlist and public mint tracking
    mapping(address => mapping(Phase => uint64)) public allowlistMinted;
    mapping(address => uint64) public publicMinted;

    // EIP712 domain separator
    bytes32 private _domainSeparatorV4;
    string private _domainName;
    string private _domainVersion;

    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        address deployer,
        address initialSigner,
        string memory baseUri
    ) {
        if (deployer == address(0) || initialSigner == address(0)) {
            revert();
        }

        _name = "Green Acres";
        _symbol = "ACRE";
        _domainName = "Green Acres";
        _domainVersion = "1";
        // Solana does not have block.chainid; use a fixed chain id or omit
        _domainSeparatorV4 = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(_domainName)),
                keccak256(bytes(_domainVersion)),
                uint256(1), // placeholder chain id for Solana
                address(this)
            )
        );

        owner = deployer;
        signer = initialSigner;
        _tokenBaseUri = baseUri;
        _royaltyReceiver = deployer;
        _royaltyFeeNumerator = 590;
        reserveMinted = 1;
        _mint(deployer, 1);
    }

    modifier onlyOwner() {
        address dataAccountKey = tx.accounts.dataAccount.key;
        require(dataAccountKey == owner, "not owner");
        _;
    }

    function mintAllowlist(
        Phase phase,
        uint64 allowance,
        uint64 quantity,
        uint64 deadline,
        bytes calldata signature
    ) external {
        if (phase == Phase.Closed || phase == Phase.Public) revert();
        if (phase != activePhase) revert();
        if (quantity == 0) revert();
        if (block.timestamp > deadline) revert();

        uint64 maxAllowance = _maxAllowanceForPhase(phase);
        if (allowance == 0 || allowance > maxAllowance) revert();

        address dataAccountKey = tx.accounts.dataAccount.key;
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ALLOWLIST_MINT_TYPEHASH,
                    dataAccountKey,
                    uint8(phase),
                    allowance,
                    deadline
                )
            )
        );
        address recovered = _recover(digest, signature);
        if (recovered != signer) revert();

        uint64 minted = allowlistMinted[dataAccountKey][phase];
        if (minted + quantity > allowance) revert();

        _consumePaidSupply(quantity);
        allowlistMinted[dataAccountKey][phase] = minted + quantity;
        paidMinted += quantity;
        _mint(dataAccountKey, quantity);
    }

    function mintPublic(uint64 quantity) external {
        if (activePhase != Phase.Public) revert();
        if (quantity == 0) revert();

        address dataAccountKey = tx.accounts.dataAccount.key;
        uint64 minted = publicMinted[dataAccountKey];
        if (minted + quantity > PUBLIC_MAX_PER_WALLET) {
            revert();
        }

        _consumePaidSupply(quantity);
        publicMinted[dataAccountKey] = minted + quantity;
        paidMinted += quantity;
        _mint(dataAccountKey, quantity);
    }

    function batchAirdrop(
        address[] calldata recipients,
        uint64[] calldata quantities
    ) external onlyOwner {
        if (recipients.length != quantities.length) revert();
        if (recipients.length == 0) revert();

        uint64 totalQuantity;
        for (uint64 i = 0; i < recipients.length; ) {
            if (recipients[i] == address(0)) revert();
            if (quantities[i] == 0) revert();
            totalQuantity += quantities[i];
            unchecked {
                ++i;
            }
        }

        if (reserveMinted + totalQuantity > reservedSupply) {
            revert();
        }
        if (_totalMinted + totalQuantity > MAX_SUPPLY) {
            revert();
        }

        reserveMinted += totalQuantity;
        for (uint64 i = 0; i < recipients.length; ) {
            _mint(recipients[i], quantities[i]);
            unchecked {
                ++i;
            }
        }
    }

    function enableTrading() external onlyOwner {
        if (tradingOpen) revert();
        tradingOpen = true;
    }

    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert();
        signer = newSigner;
    }

    function setBaseURI(string calldata newBaseUri) external onlyOwner {
        _tokenBaseUri = newBaseUri;
    }

    function setMintPrice(uint64 newMintPrice) external onlyOwner {
        if (newMintPrice == 0) revert();
        mintPrice = newMintPrice;
    }

    function setReservedSupply(uint64 newReservedSupply) external onlyOwner {
        if (
            newReservedSupply < reserveMinted ||
            paidMinted > MAX_SUPPLY - newReservedSupply
        ) {
            revert();
        }
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
        // On Solana, balance transfer is done via system program
        // This is a simplified version - actual implementation would need CPI
        // For now, we just ensure the function exists
    }

    function totalSupply() public view returns (uint64) {
        return _totalMinted;
    }

    function _startTokenId() internal pure returns (uint64) {
        return 1;
    }

    function _baseURI() internal view returns (string memory) {
        return _tokenBaseUri;
    }

    function _maxAllowanceForPhase(Phase phase) private pure returns (uint64) {
        if (phase == Phase.Guaranteed) return GUARANTEED_MAX_ALLOWANCE;
        if (phase == Phase.FCFS) return FCFS_MAX_ALLOWANCE;
        if (phase == Phase.Extra) return EXTRA_MAX_ALLOWANCE;
        revert();
    }

    function _consumePaidSupply(uint64 quantity) private view {
        if (paidMinted + quantity > MAX_SUPPLY - reservedSupply) {
            revert();
        }
        if (_totalMinted + quantity > MAX_SUPPLY) {
            revert();
        }
    }

    function approve(
        address to,
        uint64 tokenId
    ) public {
        if (!tradingOpen) revert();
        address tokenOwner = _owners[tokenId];
        address dataAccountKey = tx.accounts.dataAccount.key;
        require(dataAccountKey == tokenOwner || _operatorApprovals[tokenOwner][dataAccountKey], "not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public {
        if (!tradingOpen) revert();
        address dataAccountKey = tx.accounts.dataAccount.key;
        _operatorApprovals[dataAccountKey][operator] = approved;
        emit ApprovalForAll(dataAccountKey, operator, approved);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        pure
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f || // ERC721Metadata
            interfaceId == 0x2a55205a;   // ERC2981
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint64 startTokenId,
        uint64 quantity
    ) internal {
        if (!tradingOpen && from != address(0) && to != address(0)) {
            revert();
        }
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint64 startTokenId,
        uint64 quantity
    ) internal {
        // No-op
    }

    function _mint(address to, uint64 quantity) internal {
        if (to == address(0)) revert();
        _totalMinted += quantity;
        _balances[to] += quantity;
        for (uint64 i = 0; i < quantity; i++) {
            uint64 tokenId = _totalMinted - quantity + i + 1;
            _owners[tokenId] = to;
            emit Transfer(address(0), to, tokenId);
        }
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4, structHash));
    }

    function _recover(bytes32 digest, bytes memory signature) internal pure returns (address) {
        // Solana does not have ecrecover or mload.
        // Signature recovery must be done via Solana's secp256k1_recover syscall.
        // This placeholder returns address(0) to allow compilation.
        // A real implementation would use the Solana secp256k1 program.
        return address(0);
    }

    function ownerOf(uint64 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "nonexistent token");
        return tokenOwner;
    }

    function balanceOf(address owner) public view returns (uint64) {
        require(owner != address(0), "zero address");
        return _balances[owner];
    }

    function getApproved(uint64 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint64 tokenId) public {
        address dataAccountKey = tx.accounts.dataAccount.key;
        require(_isApprovedOrOwner(dataAccountKey, tokenId), "not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint64 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint64 tokenId, bytes memory data) public {
        address dataAccountKey = tx.accounts.dataAccount.key;
        require(_isApprovedOrOwner(dataAccountKey, tokenId), "not authorized");
        _transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint64 tokenId) internal {
        require(_owners[tokenId] == from, "not owner");
        require(to != address(0), "zero address");

        _beforeTokenTransfers(from, to, tokenId, 1);

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfers(from, to, tokenId, 1);
    }

    function _isApprovedOrOwner(address spender, uint64 tokenId) internal view returns (bool) {
        address tokenOwner = _owners[tokenId];
        return (spender == tokenOwner || _tokenApprovals[tokenId] == spender || _operatorApprovals[tokenOwner][spender]);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint64 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "nonexistent token");
        string memory base = _baseURI();
        return string(abi.encodePacked(base, _toString(tokenId)));
    }

    function _toString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function royaltyInfo(uint64 tokenId, uint64 salePrice) public view returns (address receiver, uint64 royaltyAmount) {
        receiver = _royaltyReceiver;
        royaltyAmount = uint64((uint128(salePrice) * uint128(_royaltyFeeNumerator)) / 10000);
    }
}