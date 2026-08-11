// SPDX-License-Identifier: MIT

import { AccountInfo } from "solana";

// Forward declare structs that would normally come from SeaDropStructs.sol
struct PublicDrop {
    uint64 startTime;
    uint64 endTime;
    uint64 maxTotalMintableByWallet;
    uint64 feeBps;
    bool restrictFeeRecipients;
}

struct AllowListData {
    bytes32 merkleRoot;
    string uri;
}

struct TokenGatedDropStage {
    uint64 maxTotalMintableByWallet;
    uint64 maxTotalMintableByWalletPerToken;
    uint64 dropStageIndex;
}

struct SignedMintValidationParams {
    uint64 minMintPrice;
    uint64 maxMaxTotalMintableByWallet;
    uint64 minMaxTokenSupplyForStage;
    uint64 maxMaxTokenSupplyForStage;
    uint64 minMaxTotalMintableByWallet;
    uint64 maxMaxTotalMintableByWallet;
    uint64 minMaxTotalMintableByWalletPerToken;
    uint64 maxMaxTotalMintableByWalletPerToken;
    uint64 minDropStageIndex;
    uint64 maxDropStageIndex;
}

// Minimal ERC721A base contract
contract ERC721A {
    string internal _name;
    string internal _symbol;

    mapping(uint64 => address) internal _owners;
    mapping(address => uint64) internal _balances;
    mapping(uint64 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    uint64 internal _currentIndex;
    uint64 internal _burnCounter;

    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _currentIndex = _startTokenId();
    }

    function _startTokenId() internal view virtual returns (uint64) {
        return 1;
    }

    function _exists(uint64 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _totalMinted() internal view virtual returns (uint64) {
        return _currentIndex - _startTokenId();
    }

    function totalSupply() public view virtual returns (uint64) {
        return _currentIndex - _burnCounter - _startTokenId();
    }

    function _numberMinted(address owner) internal view virtual returns (uint64) {
        // Simplified: in a real ERC721A this would track per-address mint counts
        return _balances[owner];
    }

    function _safeMint(address to, uint64 quantity) internal virtual {
        _mint(to, quantity);
    }

    function _mint(address to, uint64 quantity) internal virtual {
        uint64 startTokenId = _currentIndex;
        for (uint64 i = 0; i < quantity; i++) {
            _owners[startTokenId + i] = to;
            emit Transfer(address(0), to, startTokenId + i);
        }
        _balances[to] += quantity;
        _currentIndex += quantity;
    }

    function _burn(uint64 tokenId, bool approvalCheck) internal virtual {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721A: nonexistent token");

        if (approvalCheck) {
            require(
                owner == tx.accounts.dataAccount.key ||
                _tokenApprovals[tokenId] == tx.accounts.dataAccount.key ||
                _operatorApprovals[owner][tx.accounts.dataAccount.key],
                "ERC721A: not approved"
            );
        }

        _balances[owner] -= 1;
        delete _owners[tokenId];
        _burnCounter += 1;

        emit Transfer(owner, address(0), tokenId);
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

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x80ac58cd || interfaceId == 0x5b5e139f || interfaceId == 0x01ffc9a7;
    }
}

// Minimal ISeaDrop interface
interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata publicDrop) external;
    function updateAllowList(AllowListData calldata allowListData) external;
    function updateTokenGatedDrop(address allowedNftToken, TokenGatedDropStage calldata dropStage) external;
    function updateDropURI(string calldata dropURI) external;
    function updateCreatorPayoutAddress(address payoutAddress) external;
    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external;
    function updateSignedMintValidationParams(address signer, SignedMintValidationParams memory params) external;
    function updatePayer(address payer, bool allowed) external;
}

@program_id("11111111111111111111111111111111")
contract ERC721SeaDrop is ERC721A {
    // Events
    event SeaDropTokenDeployed();
    event AllowedSeaDropUpdated(address[] allowedSeaDrop);

    // State variables
    mapping(address => bool) internal _allowedSeaDrop;
    address[] internal _enumeratedAllowedSeaDrop;
    uint64 internal _maxSupply;
    string internal _baseURIValue;
    string internal _contractURIValue;
    bytes32 internal _provenanceHash;

    // Owner address
    address internal _owner;

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function _onlyOwnerOrSelf() internal view {
        require(
            tx.accounts.dataAccount.key == _owner || tx.accounts.dataAccount.key == address(this),
            "Not owner or self"
        );
    }

    function _onlyAllowedSeaDrop(address seaDrop) internal view {
        require(_allowedSeaDrop[seaDrop] == true, "OnlyAllowedSeaDrop");
    }

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop
    ) ERC721A(name, symbol) {
        _owner = tx.accounts.dataAccount.key;

        uint64 allowedSeaDropLength = uint64(allowedSeaDrop.length);

        for (uint64 i = 0; i < allowedSeaDropLength; ) {
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
        uint64 enumeratedAllowedSeaDropLength = uint64(_enumeratedAllowedSeaDrop.length);
        uint64 allowedSeaDropLength = uint64(allowedSeaDrop.length);

        for (uint64 i = 0; i < enumeratedAllowedSeaDropLength; ) {
            _allowedSeaDrop[_enumeratedAllowedSeaDrop[i]] = false;
            unchecked {
                ++i;
            }
        }

        for (uint64 i = 0; i < allowedSeaDropLength; ) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        _enumeratedAllowedSeaDrop = allowedSeaDrop;

        emit AllowedSeaDropUpdated(allowedSeaDrop);
    }

    function burn(uint64 tokenId) external {
        _burn(tokenId, true);
    }

    function _startTokenId() internal view virtual override returns (uint64) {
        return 1;
    }

    function tokenURI(uint64 tokenId)
        public
        view
        virtual
        returns (string memory)
    {
        require(_exists(tokenId), "URIQueryForNonexistentToken");

        string memory baseURI = _baseURI();

        if (bytes(baseURI).length == 0) {
            return "";
        }

        if (bytes(baseURI)[bytes(baseURI).length - 1] != bytes("/")[0]) {
            return baseURI;
        }

        return string(abi.encodePacked(baseURI, _toString(tokenId)));
    }

    function mintSeaDrop(address minter, uint64 quantity)
        external
        virtual
    {
        _onlyAllowedSeaDrop(tx.accounts.dataAccount.key);

        require(
            _totalMinted() + quantity <= maxSupply(),
            "MintQuantityExceedsMaxSupply"
        );

        _safeMint(minter, quantity);
    }

    function updatePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external virtual {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updatePublicDrop{accounts: [tx.accounts.dataAccount]}(publicDrop);
    }

    function updateAllowList(
        address seaDropImpl,
        AllowListData calldata allowListData
    ) external virtual {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowList{accounts: [tx.accounts.dataAccount]}(allowListData);
    }

    function updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage calldata dropStage
    ) external virtual {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateTokenGatedDrop{accounts: [tx.accounts.dataAccount]}(allowedNftToken, dropStage);
    }

    function updateDropURI(address seaDropImpl, string calldata dropURI)
        external
        virtual
    {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateDropURI{accounts: [tx.accounts.dataAccount]}(dropURI);
    }

    function updateCreatorPayoutAddress(
        address seaDropImpl,
        address payoutAddress
    ) external {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateCreatorPayoutAddress{accounts: [tx.accounts.dataAccount]}(payoutAddress);
    }

    function updateAllowedFeeRecipient(
        address seaDropImpl,
        address feeRecipient,
        bool allowed
    ) external virtual {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowedFeeRecipient{accounts: [tx.accounts.dataAccount]}(feeRecipient, allowed);
    }

    function updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) external virtual {
        _onlyOwnerOrSelf();
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateSignedMintValidationParams{accounts: [tx.accounts.dataAccount]}(
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
        ISeaDrop(seaDropImpl).updatePayer{accounts: [tx.accounts.dataAccount]}(payer, allowed);
    }

    function getMintStats(address minter)
        external
        view
        returns (
            uint64 minterNumMinted,
            uint64 currentTotalSupply,
            uint64 maxSupplyValue
        )
    {
        minterNumMinted = _numberMinted(minter);
        currentTotalSupply = _totalMinted();
        maxSupplyValue = _maxSupply;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function maxSupply() public view returns (uint64) {
        return _maxSupply;
    }

    function setMaxSupply(uint64 newMaxSupply) external {
        _onlyOwnerOrSelf();
        _maxSupply = newMaxSupply;
    }

    function _baseURI() internal view virtual returns (string memory) {
        return _baseURIValue;
    }

    function setBaseURI(string calldata baseURI) external {
        _onlyOwnerOrSelf();
        _baseURIValue = baseURI;
    }

    function setContractURI(string calldata contractURI) external {
        _onlyOwnerOrSelf();
        _contractURIValue = contractURI;
    }

    function setProvenanceHash(bytes32 provenanceHash) external {
        _onlyOwnerOrSelf();
        _provenanceHash = provenanceHash;
    }

    function _cast(bool b) internal pure returns (uint64) {
        return b ? 1 : 0;
    }

    struct MultiConfigureStruct {
        uint64 maxSupply;
        string baseURI;
        string contractURI;
        address seaDropImpl;
        PublicDrop publicDrop;
        string dropURI;
        AllowListData allowListData;
        address creatorPayoutAddress;
        bytes32 provenanceHash;
        address[] allowedFeeRecipients;
        address[] disallowedFeeRecipients;
        address[] allowedPayers;
        address[] disallowedPayers;
        address[] tokenGatedAllowedNftTokens;
        TokenGatedDropStage[] tokenGatedDropStages;
        address[] disallowedTokenGatedAllowedNftTokens;
        address[] signers;
        SignedMintValidationParams[] signedMintValidationParams;
        address[] disallowedSigners;
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
            for (uint64 i = 0; i < config.allowedFeeRecipients.length; ) {
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
            for (uint64 i = 0; i < config.disallowedFeeRecipients.length; ) {
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
            for (uint64 i = 0; i < config.allowedPayers.length; ) {
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
            for (uint64 i = 0; i < config.disallowedPayers.length; ) {
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
            require(
                config.tokenGatedDropStages.length ==
                config.tokenGatedAllowedNftTokens.length,
                "TokenGatedMismatch"
            );
            for (uint64 i = 0; i < config.tokenGatedDropStages.length; ) {
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
                uint64 i = 0;
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
            require(
                config.signedMintValidationParams.length ==
                config.signers.length,
                "SignersMismatch"
            );
            for (
                uint64 i = 0;
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
            for (uint64 i = 0; i < config.disallowedSigners.length; ) {
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
}