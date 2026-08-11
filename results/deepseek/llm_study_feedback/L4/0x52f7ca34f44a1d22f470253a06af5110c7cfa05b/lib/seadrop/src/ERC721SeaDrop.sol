// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Minimal stubs for missing dependencies to allow compilation on Solana via Solang.
// In a full port, these would be properly implemented or replaced with Solana-native patterns.

interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata publicDrop) external;
    function updateAllowList(AllowListData calldata allowListData) external;
    function updateTokenGatedDrop(address allowedNftToken, TokenGatedDropStage calldata dropStage) external;
    function updateDropURI(string calldata dropURI) external;
    function updateCreatorPayoutAddress(address payoutAddress) external;
    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external;
    function updateSignedMintValidationParams(address signer, SignedMintValidationParams memory signedMintValidationParams) external;
    function updatePayer(address payer, bool allowed) external;
}

struct PublicDrop {
    uint256 startTime;
    uint256 endTime;
}

struct AllowListData {
    bytes32 merkleRoot;
}

struct TokenGatedDropStage {
    // minimal stub
    uint256 dummy;
}

struct SignedMintValidationParams {
    // minimal stub
    uint256 dummy;
}

interface ISeaDropTokenContractMetadata {
    function setMaxSupply(uint256 newMaxSupply) external;
    function setBaseURI(string calldata newBaseURI) external;
    function setContractURI(string calldata newContractURI) external;
    function setProvenanceHash(bytes32 newProvenanceHash) external;
}

interface INonFungibleSeaDropToken {
    function mintSeaDrop(address minter, uint256 quantity) external;
    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external;
    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData) external;
    function updateTokenGatedDrop(address seaDropImpl, address allowedNftToken, TokenGatedDropStage calldata dropStage) external;
    function updateDropURI(address seaDropImpl, string calldata dropURI) external;
    function updateSignedMintValidationParams(address seaDropImpl, address signer, SignedMintValidationParams memory signedMintValidationParams) external;
    function updatePayer(address seaDropImpl, address payer, bool allowed) external;
    function getMintStats(address minter) external view returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply);
}

struct MultiConfigureStruct {
    uint256 maxSupply;
    string baseURI;
    string contractURI;
    PublicDrop publicDrop;
    string dropURI;
    AllowListData allowListData;
    address creatorPayoutAddress;
    bytes32 provenanceHash;
    address[] allowedFeeRecipients;
    address[] disallowedFeeRecipients;
    address[] allowedPayers;
    address[] disallowedPayers;
    TokenGatedDropStage[] tokenGatedDropStages;
    address[] tokenGatedAllowedNftTokens;
    address[] disallowedTokenGatedAllowedNftTokens;
    SignedMintValidationParams[] signedMintValidationParams;
    address[] signers;
    address[] disallowedSigners;
    address seaDropImpl;
}

// Minimal ERC721A stub for Solang
contract ERC721A {
    string private _name;
    string private _symbol;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _currentIndex;
    uint256 private _burnCounter;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _currentIndex = _startTokenId();
    }

    function _startTokenId() internal view virtual returns (uint256) {
        return 1;
    }

    function totalSupply() public view returns (uint256) {
        return _currentIndex - _burnCounter - _startTokenId();
    }

    function _totalMinted() internal view returns (uint256) {
        return _currentIndex - _startTokenId();
    }

    function _numberMinted(address owner) internal view returns (uint256) {
        // Simplified: just return balance
        return _balances[owner];
    }

    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "ERC721A: balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721A: owner query for nonexistent token");
        return owner;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _safeMint(address to, uint256 quantity) internal {
        _mint(to, quantity);
    }

    function _mint(address to, uint256 quantity) internal {
        require(to != address(0), "ERC721A: mint to the zero address");
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _currentIndex;
            _owners[tokenId] = to;
            emit Transfer(address(0), to, tokenId);
            _currentIndex++;
        }
        _balances[to] += quantity;
    }

    function _burn(uint256 tokenId, bool) internal {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721A: burn of nonexistent token");
        _balances[owner]--;
        delete _owners[tokenId];
        emit Transfer(owner, address(0), tokenId);
        _burnCounter++;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
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

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f;
    }
}

@program_id("SeaDrop1111111111111111111111111111111111111")
contract ERC721SeaDrop is ERC721A, ISeaDropTokenContractMetadata {
    // Errors and events originally from ERC721SeaDropStructsErrorsAndEvents
    error OnlyAllowedSeaDrop();
    error MintQuantityExceedsMaxSupply(uint256 total, uint256 max);
    error URIQueryForNonexistentToken();
    error TokenGatedMismatch();
    error SignersMismatch();

    event SeaDropTokenDeployed();
    event AllowedSeaDropUpdated(address[] allowedSeaDrop);

    // Reentrancy guard state (simple replacement for ReentrancyGuard)
    uint256 private _status = 1;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // Owner state (simple replacement for Ownable)
    address private _owner;

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    function _onlyOwnerOrSelf() internal view {
        require(tx.accounts[0].key == _owner || tx.accounts[0].key == address(this), "Not owner or self");
    }

    // SeaDrop allowed mapping
    mapping(address => bool) internal _allowedSeaDrop;
    address[] internal _enumeratedAllowedSeaDrop;

    // Max supply
    uint256 internal _maxSupply;

    // Base URI
    string private _baseTokenURI;

    // Contract URI
    string private _contractURI;

    // Provenance hash
    bytes32 private _provenanceHash;

    function _onlyAllowedSeaDrop(address seaDrop) internal view {
        if (_allowedSeaDrop[seaDrop] != true) {
            revert("OnlyAllowedSeaDrop");
        }
    }

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) ERC721A(name, symbol) {
        _owner = tx.accounts[0].key;

        uint256 allowedSeaDropLength = allowedSeaDrop.length;

        for (uint256 i = 0; i < allowedSeaDropLength; ) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        _enumeratedAllowedSeaDrop = allowedSeaDrop;

        emit SeaDropTokenDeployed();
    }

    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop)
        external
        virtual
        onlyOwner
    {
        _updateAllowedSeaDrop(allowedSeaDrop);
    }

    function _updateAllowedSeaDrop(address[] calldata allowedSeaDrop) internal {
        uint256 enumeratedAllowedSeaDropLength = _enumeratedAllowedSeaDrop
            .length;
        uint256 allowedSeaDropLength = allowedSeaDrop.length;

        for (uint256 i = 0; i < enumeratedAllowedSeaDropLength; ) {
            _allowedSeaDrop[_enumeratedAllowedSeaDrop[i]] = false;
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < allowedSeaDropLength; ) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        _enumeratedAllowedSeaDrop = allowedSeaDrop;

        emit AllowedSeaDropUpdated(allowedSeaDrop);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId, true);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        returns (string memory)
    {
        if (!_exists(tokenId)) revert("URIQueryForNonexistentToken");

        string memory baseURI = _baseURI();

        if (bytes(baseURI).length == 0) {
            return "";
        }

        if (bytes(baseURI)[bytes(baseURI).length - 1] != bytes("/")[0]) {
            return baseURI;
        }

        return string(abi.encodePacked(baseURI, _toString(tokenId)));
    }

    function mintSeaDrop(address minter, uint256 quantity)
        external
        virtual
        nonReentrant
    {
        _onlyAllowedSeaDrop(tx.accounts[0].key);

        if (_totalMinted() + quantity > maxSupply()) {
            revert("MintQuantityExceedsMaxSupply");
        }

        _safeMint(minter, quantity);
    }

    function updatePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updatePublicDrop(publicDrop);
    }

    function updateAllowList(
        address seaDropImpl,
        AllowListData calldata allowListData
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateAllowList(allowListData);
    }

    function updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage calldata dropStage
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateTokenGatedDrop(allowedNftToken, dropStage);
    }

    function updateDropURI(address seaDropImpl, string calldata dropURI)
        external
        virtual
    {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateDropURI(dropURI);
    }

    function updateCreatorPayoutAddress(
        address seaDropImpl,
        address payoutAddress
    ) external {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    function updateAllowedFeeRecipient(
        address seaDropImpl,
        address feeRecipient,
        bool allowed
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    function updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updateSignedMintValidationParams(
            signer,
            signedMintValidationParams
        );
    }

    function updatePayer(
        address seaDropImpl,
        address payer,
        bool allowed
    ) external virtual {
        _onlyOwnerOrSelf();

        _onlyAllowedSeaDrop(seaDropImpl);

        ISeaDrop(seaDropImpl).updatePayer(payer, allowed);
    }

    function getMintStats(address minter)
        external
        view
        returns (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        )
    {
        minterNumMinted = _numberMinted(minter);
        currentTotalSupply = _totalMinted();
        maxSupply = _maxSupply;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == bytes4(keccak256("INonFungibleSeaDropToken")) ||
            interfaceId == bytes4(keccak256("ISeaDropTokenContractMetadata")) ||
            ERC721A.supportsInterface(interfaceId);
    }

    // ISeaDropTokenContractMetadata implementation
    function setMaxSupply(uint256 newMaxSupply) external override {
        _onlyOwnerOrSelf();
        _maxSupply = newMaxSupply;
    }

    function setBaseURI(string calldata newBaseURI) external override {
        _onlyOwnerOrSelf();
        _baseTokenURI = newBaseURI;
    }

    function setContractURI(string calldata newContractURI) external override {
        _onlyOwnerOrSelf();
        _contractURI = newContractURI;
    }

    function setProvenanceHash(bytes32 newProvenanceHash) external override {
        _onlyOwnerOrSelf();
        _provenanceHash = newProvenanceHash;
    }

    function maxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    function _baseURI() internal view virtual returns (string memory) {
        return _baseTokenURI;
    }

    function multiConfigure(MultiConfigureStruct calldata config)
        external
        onlyOwner
    {
        if (config.maxSupply > 0) {
            this.setMaxSupply(config.maxSupply);
        }
        if (bytes(config.baseURI).length != 0) {
            this.setBaseURI(config.baseURI);
        }
        if (bytes(config.contractURI).length != 0) {
            this.setContractURI(config.contractURI);
        }
        if (
            _cast(config.publicDrop.startTime != 0) |
                _cast(config.publicDrop.endTime != 0) ==
            1
        ) {
            this.updatePublicDrop(config.seaDropImpl, config.publicDrop);
        }
        if (bytes(config.dropURI).length != 0) {
            this.updateDropURI(config.seaDropImpl, config.dropURI);
        }
        if (config.allowListData.merkleRoot != bytes32(0)) {
            this.updateAllowList(config.seaDropImpl, config.allowListData);
        }
        if (config.creatorPayoutAddress != address(0)) {
            this.updateCreatorPayoutAddress(
                config.seaDropImpl,
                config.creatorPayoutAddress
            );
        }
        if (config.provenanceHash != bytes32(0)) {
            this.setProvenanceHash(config.provenanceHash);
        }
        if (config.allowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < config.allowedFeeRecipients.length; ) {
                this.updateAllowedFeeRecipient(
                    config.seaDropImpl,
                    config.allowedFeeRecipients[i],
                    true
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.disallowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < config.disallowedFeeRecipients.length; ) {
                this.updateAllowedFeeRecipient(
                    config.seaDropImpl,
                    config.disallowedFeeRecipients[i],
                    false
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.allowedPayers.length > 0) {
            for (uint256 i = 0; i < config.allowedPayers.length; ) {
                this.updatePayer(
                    config.seaDropImpl,
                    config.allowedPayers[i],
                    true
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.disallowedPayers.length > 0) {
            for (uint256 i = 0; i < config.disallowedPayers.length; ) {
                this.updatePayer(
                    config.seaDropImpl,
                    config.disallowedPayers[i],
                    false
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.tokenGatedDropStages.length > 0) {
            if (
                config.tokenGatedDropStages.length !=
                config.tokenGatedAllowedNftTokens.length
            ) {
                revert("TokenGatedMismatch");
            }
            for (uint256 i = 0; i < config.tokenGatedDropStages.length; ) {
                this.updateTokenGatedDrop(
                    config.seaDropImpl,
                    config.tokenGatedAllowedNftTokens[i],
                    config.tokenGatedDropStages[i]
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.disallowedTokenGatedAllowedNftTokens.length > 0) {
            for (
                uint256 i = 0;
                i < config.disallowedTokenGatedAllowedNftTokens.length;

            ) {
                TokenGatedDropStage memory emptyStage;
                this.updateTokenGatedDrop(
                    config.seaDropImpl,
                    config.disallowedTokenGatedAllowedNftTokens[i],
                    emptyStage
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.signedMintValidationParams.length > 0) {
            if (
                config.signedMintValidationParams.length !=
                config.signers.length
            ) {
                revert("SignersMismatch");
            }
            for (
                uint256 i = 0;
                i < config.signedMintValidationParams.length;

            ) {
                this.updateSignedMintValidationParams(
                    config.seaDropImpl,
                    config.signers[i],
                    config.signedMintValidationParams[i]
                );
                unchecked {
                    ++i;
                }
            }
        }
        if (config.disallowedSigners.length > 0) {
            for (uint256 i = 0; i < config.disallowedSigners.length; ) {
                SignedMintValidationParams memory emptyParams;
                this.updateSignedMintValidationParams(
                    config.seaDropImpl,
                    config.disallowedSigners[i],
                    emptyParams
                );
                unchecked {
                    ++i;
                }
            }
        }
    }

    function _cast(bool b) internal pure returns (uint256) {
        return b ? 1 : 0;
    }
}