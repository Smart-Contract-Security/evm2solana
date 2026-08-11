// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';
import {IERC721MetadataUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ERC721Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import {IERC5192} from './interfaces/IERC5192.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {EIP712Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';

/**
 * @title SoulBoundNFTCosigned
 * @notice Soulbound NFT with cosigner authority for cross-chain solutions
 * @dev Uses EIP-712 signatures for minting and transfer authorization
 */
contract SoulBoundNFTCosigned is 
    Initializable, 
    ERC721Upgradeable, 
    EIP712Upgradeable,
    PausableUpgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable,
    IERC5192
{
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Boolean to represent that the URIs for the collection can never be modified again
    bool public lockURI;

    /// @dev Mapping of individual token ID to URI
    mapping(uint256 => string) public newURI;

    /// @dev Base URI for collection metadata
    string internal baseURI;

    /// @dev Authority address that cosigns transactions
    address public authority;

    /// @dev Nonces for preventing signature replay attacks
    mapping(address => uint256) public nonces;

    /// @dev Treasury address to receive mint fees
    address public treasury;

    /// @dev Mint fee in wei per token
    uint256 public mintFee;

    /// @dev Maximum number of tokens mintable via the claim path
    uint256 public claimSupply;

    /// @dev Number of tokens minted via the claim path so far
    uint256 public claimsMinted;

    /// @dev Tracks which token IDs were minted via the limited claim path (non-transferable)
    mapping(uint256 => bool) public isClaimToken;

    /*//////////////////////////////////////////////////////////////
                              STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    uint256[38] private __gap;

    /*//////////////////////////////////////////////////////////////
                              TYPE HASHES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant MINT_TYPEHASH = 
        keccak256("Mint(address to,uint256 tokenId,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant MINT_BATCH_TYPEHASH = 
        keccak256("MintBatch(address to,uint256[] tokenIds,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant TRANSFER_TYPEHASH = 
        keccak256("Transfer(address from,address to,uint256 tokenId,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant TRANSFER_BATCH_TYPEHASH = 
        keccak256("TransferBatch(address from,address to,uint256[] tokenIds,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant MINT_AND_TRANSFER_BATCH_TYPEHASH = 
        keccak256("MintAndTransferBatch(address to,uint256[] mintTokenIds,uint256[] transferTokenIds,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant CLAIM_TYPEHASH = 
        keccak256("Claim(address to,uint256 tokenId,uint256 nonce,uint256 deadline)");
    
    bytes32 public constant CLAIM_BATCH_TYPEHASH = 
        keccak256("ClaimBatch(address to,uint256[] tokenIds,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuthorityUpdated(address indexed oldAuthority, address indexed newAuthority);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event ClaimSupplyUpdated(uint256 oldSupply, uint256 newSupply);

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error SoulBoundNFTCosigned__InvalidAuthority();
    error SoulBoundNFTCosigned__InvalidSignature();
    error SoulBoundNFTCosigned__ExpiredSignature();
    error SoulBoundNFTCosigned__LockedURI();
    error SoulBoundNFTCosigned__UndefinedParam();
    error SoulBoundNFTCosigned__InvalidNonce();
    error SoulBoundNFTCosigned__InsufficientPayment();
    error SoulBoundNFTCosigned__TransferFailed();
    error SoulBoundNFTCosigned__InvalidTreasury();
    error SoulBoundNFTCosigned__ClaimSupplyExceeded();
    error SoulBoundNFTCosigned__ClaimTokenNonTransferable();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert SoulBoundNFTCosigned__ExpiredSignature();
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC721Upgradeable) 
        returns (bool) 
    {
        return
            interfaceId == type(IERC721Upgradeable).interfaceId ||
            interfaceId == type(IERC721MetadataUpgradeable).interfaceId ||
            interfaceId == type(IERC5192).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /*///////////////////////////////////////////////////////////////
                            Initializer
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address authority_,
        address owner_
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __EIP712_init(name_, "1");
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        
        _pause();

        if (authority_ == address(0)) revert SoulBoundNFTCosigned__InvalidAuthority();
        authority = authority_;
        baseURI = baseURI_;

        if (owner_ != address(0)) {
            transferOwnership(owner_);
        }

        emit AuthorityUpdated(address(0), authority_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////////////
                            Authority Management
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the authority address
     * @param newAuthority_ The new authority address
     */
    function setAuthority(address newAuthority_) external onlyOwner {
        if (newAuthority_ == address(0)) revert SoulBoundNFTCosigned__InvalidAuthority();
        
        address oldAuthority = authority;
        authority = newAuthority_;
        
        emit AuthorityUpdated(oldAuthority, newAuthority_);
    }

    /*///////////////////////////////////////////////////////////////
                            Treasury & Fee Management
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the treasury address
     * @param newTreasury_ The new treasury address
     */
    function setTreasury(address newTreasury_) external onlyOwner {
        if (newTreasury_ == address(0)) revert SoulBoundNFTCosigned__InvalidTreasury();
        
        address oldTreasury = treasury;
        treasury = newTreasury_;
        
        emit TreasuryUpdated(oldTreasury, newTreasury_);
    }

    /**
     * @notice Updates the mint fee
     * @param newMintFee_ The new mint fee in wei per token
     */
    function setMintFee(uint256 newMintFee_) external onlyOwner {
        uint256 oldFee = mintFee;
        mintFee = newMintFee_;
        
        emit MintFeeUpdated(oldFee, newMintFee_);
    }

    /**
     * @notice Calculates the total fee for minting tokens
     * @param tokenCount Number of tokens to mint
     * @return Total fee in wei
     */
    function calculateMintFee(uint256 tokenCount) public view returns (uint256) {
        return mintFee * tokenCount;
    }

    /**
     * @notice Updates the claim supply cap
     * @param newClaimSupply_ The new maximum number of claimable tokens
     */
    function setClaimSupply(uint256 newClaimSupply_) external onlyOwner {
        uint256 oldSupply = claimSupply;
        claimSupply = newClaimSupply_;
        
        emit ClaimSupplyUpdated(oldSupply, newClaimSupply_);
    }

    /*///////////////////////////////////////////////////////////////
                            Token Metadata
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the Base URI of the collection
     */
    function _baseURI() internal view override(ERC721Upgradeable) returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Allows the owner to modify the base URI of the collection
     */
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        if (lockURI) revert SoulBoundNFTCosigned__LockedURI();
        baseURI = newBaseURI;
    }

    /**
     * @dev Allows the owner to modify the URI for a specific token ID in the collection
     */
    function setTokenURI(uint256 tokenId, string memory newTokenURI) public onlyOwner {
        if (lockURI) revert SoulBoundNFTCosigned__LockedURI();
        newURI[tokenId] = newTokenURI;
    }

    /**
     * @dev View the tokenURI for a given token ID
     */
    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable) returns (string memory) {
        if (bytes(newURI[tokenId]).length != 0) {
            return newURI[tokenId];
        } else {
            return super.tokenURI(tokenId);
        }
    }

    /**
     * @dev Lock the base URI modification forever
     */
    function lockURIforever() external onlyOwner {
        lockURI = true;
    }

    /*///////////////////////////////////////////////////////////////
                                Pausable
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Pause minting
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause minting
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                                Mint
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints a token to an address with authority signature
     * @param to Address to mint to
     * @param tokenId Token ID to mint
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function mint(
        address to,
        uint256 tokenId,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused validDeadline(deadline) {
        _collectMintFee(1);
        
        uint256 currentNonce = nonces[to];
        
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_TYPEHASH,
                to,
                tokenId,
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[to]++;
        _safeMint(to, tokenId);
        emit Locked(tokenId);
    }

    /**
     * @notice Mints multiple tokens to an address with authority signature
     * @param to Address to mint to
     * @param tokenIds Token IDs to mint
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function mintBatch(
        address to,
        uint256[] calldata tokenIds,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused validDeadline(deadline) {
        _collectMintFee(tokenIds.length);
        
        uint256 currentNonce = nonces[to];
        
        bytes32 structHash = keccak256(
            abi.encode(
                MINT_BATCH_TYPEHASH,
                to,
                keccak256(abi.encodePacked(tokenIds)),
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[to]++;
        
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _safeMint(to, tokenIds[i]);
            emit Locked(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                                Claim (Limited Supply)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims a token from the limited supply, soulbound to msg.sender permanently
     * @dev These tokens can never be transferred, even via cosigned transfer
     * @param tokenId Token ID to claim
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function claim(
        uint256 tokenId,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused validDeadline(deadline) {
        _collectMintFee(1);
        
        if (claimsMinted + 1 > claimSupply) revert SoulBoundNFTCosigned__ClaimSupplyExceeded();
        
        address to = msg.sender;
        uint256 currentNonce = nonces[to];
        
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                to,
                tokenId,
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[to]++;
        claimsMinted++;
        isClaimToken[tokenId] = true;
        
        _safeMint(to, tokenId);
        emit Locked(tokenId);
    }

    /**
     * @notice Claims multiple tokens from the limited supply, soulbound to msg.sender permanently
     * @dev These tokens can never be transferred, even via cosigned transfer
     * @param tokenIds Token IDs to claim
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function claimBatch(
        uint256[] calldata tokenIds,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused validDeadline(deadline) {
        uint256 len = tokenIds.length;
        _collectMintFee(len);
        
        if (claimsMinted + len > claimSupply) revert SoulBoundNFTCosigned__ClaimSupplyExceeded();
        
        address to = msg.sender;
        uint256 currentNonce = nonces[to];
        
        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_BATCH_TYPEHASH,
                to,
                keccak256(abi.encodePacked(tokenIds)),
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[to]++;
        claimsMinted += len;
        
        for (uint256 i = 0; i < len; ) {
            isClaimToken[tokenIds[i]] = true;
            _safeMint(to, tokenIds[i]);
            emit Locked(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                                Transfer
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers a token with authority signature
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param tokenId Token ID to transfer
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function transferFromCosigned(
        address from,
        address to,
        uint256 tokenId,
        uint256 deadline,
        bytes calldata signature
    ) public whenNotPaused validDeadline(deadline) {
        uint256 currentNonce = nonces[from];
        
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                from,
                to,
                tokenId,
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[from]++;
        _transfer(from, to, tokenId);
    }

    /**
     * @notice Safe transfer with authority signature
     */
    function safeTransferFromCosigned(
        address from,
        address to,
        uint256 tokenId,
        uint256 deadline,
        bytes calldata signature
    ) public whenNotPaused validDeadline(deadline) {
        uint256 currentNonce = nonces[from];
        
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                from,
                to,
                tokenId,
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[from]++;
        _safeTransfer(from, to, tokenId, '');
    }

    /**
     * @notice Transfers multiple tokens with authority signature
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param tokenIds Token IDs to transfer
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function transferBatchCosigned(
        address from,
        address to,
        uint256[] calldata tokenIds,
        uint256 deadline,
        bytes calldata signature
    ) public whenNotPaused validDeadline(deadline) {
        uint256 currentNonce = nonces[from];
        
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_BATCH_TYPEHASH,
                from,
                to,
                keccak256(abi.encodePacked(tokenIds)),
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[from]++;
        
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _transfer(from, to, tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Safe transfers multiple tokens with authority signature
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param tokenIds Token IDs to transfer
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     */
    function safeTransferBatchCosigned(
        address from,
        address to,
        uint256[] calldata tokenIds,
        uint256 deadline,
        bytes calldata signature
    ) public whenNotPaused validDeadline(deadline) {
        uint256 currentNonce = nonces[from];
        
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_BATCH_TYPEHASH,
                from,
                to,
                keccak256(abi.encodePacked(tokenIds)),
                currentNonce,
                deadline
            )
        );
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        
        if (signer != authority) revert SoulBoundNFTCosigned__InvalidSignature();
        
        nonces[from]++;
        
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _safeTransfer(from, to, tokenIds[i], '');
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Mints multiple tokens and transfers multiple tokens to the same recipient in a single transaction
     * @param to Recipient address for both minted and transferred tokens
     * @param mintTokenIds Token IDs to mint to the recipient
     * @param transferTokenIds Token IDs to transfer to the recipient (from their current owners)
     * @param deadline Signature expiration timestamp
     * @param signature Authority signature
     * @dev The nonce used is based on the recipient address (to). Fee is only charged for mints, not transfers.
     *      Transfers are executed from the current owner of each token.
     */
    function mintAndTransferBatchCosigned(
        address to,
        uint256[] calldata mintTokenIds,
        uint256[] calldata transferTokenIds,
        uint256 deadline,
        bytes calldata signature
    ) external payable whenNotPaused validDeadline(deadline) {
        _collectMintFee(mintTokenIds.length);
        _verifyMintAndTransferSignature(to, mintTokenIds, transferTokenIds, deadline, signature);
        
        nonces[to]++;
        
        _executeMintBatch(to, mintTokenIds);
        _executeTransferBatchFromOwners(to, transferTokenIds);
    }
    
    /**
     * @dev Verifies the signature for mintAndTransferBatchCosigned
     */
    function _verifyMintAndTransferSignature(
        address to,
        uint256[] calldata mintTokenIds,
        uint256[] calldata transferTokenIds,
        uint256 deadline,
        bytes calldata signature
    ) internal view {
        bytes32 mintHash = keccak256(abi.encodePacked(mintTokenIds));
        bytes32 transferHash = keccak256(abi.encodePacked(transferTokenIds));
        
        bytes32 structHash = _buildMintAndTransferStructHash(
            to, mintHash, transferHash, deadline
        );
        
        if (_hashTypedDataV4(structHash).recover(signature) != authority) {
            revert SoulBoundNFTCosigned__InvalidSignature();
        }
    }
    
    /**
     * @dev Builds the struct hash for mintAndTransferBatchCosigned
     */
    function _buildMintAndTransferStructHash(
        address to,
        bytes32 mintHash,
        bytes32 transferHash,
        uint256 deadline
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                MINT_AND_TRANSFER_BATCH_TYPEHASH,
                to,
                mintHash,
                transferHash,
                nonces[to],
                deadline
            )
        );
    }
    
    /**
     * @dev Executes batch minting
     */
    function _executeMintBatch(address to, uint256[] calldata tokenIds) internal {
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _safeMint(to, tokenIds[i]);
            emit Locked(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @dev Executes batch transfer
     */
    function _executeTransferBatch(address from, address to, uint256[] calldata tokenIds) internal {
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            _safeTransfer(from, to, tokenIds[i], '');
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @dev Executes batch transfer from current owners of each token
     */
    function _executeTransferBatchFromOwners(address to, uint256[] calldata tokenIds) internal {
        uint256 len = tokenIds.length;
        for (uint256 i = 0; i < len; ) {
            address currentOwner = ownerOf(tokenIds[i]);
            _transfer(currentOwner, to, tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Blocks transfer of claim tokens. Only minting (from == address(0)) is allowed.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        
        if (from != address(0) && isClaimToken[firstTokenId]) {
            revert SoulBoundNFTCosigned__ClaimTokenNonTransferable();
        }
    }

    /**
     * @dev Collects mint fee and sends to treasury
     * @param tokenCount Number of tokens being minted
     */
    function _collectMintFee(uint256 tokenCount) internal {
        uint256 totalFee = mintFee * tokenCount;
        
        if (totalFee > 0) {
            if (msg.value < totalFee) revert SoulBoundNFTCosigned__InsufficientPayment();
            
            if (treasury != address(0)) {
                (bool success, ) = treasury.call{value: totalFee}("");
                if (!success) revert SoulBoundNFTCosigned__TransferFailed();
            }
            
            // Refund excess payment
            uint256 excess = msg.value - totalFee;
            if (excess > 0) {
                (bool refundSuccess, ) = msg.sender.call{value: excess}("");
                if (!refundSuccess) revert SoulBoundNFTCosigned__TransferFailed();
            }
        }
    }

    /**
     * @dev Override standard transfer functions to prevent direct transfers
     */
    function transferFrom(address, address, uint256) public pure override {
        revert SoulBoundNFTCosigned__InvalidSignature();
    }

    function safeTransferFrom(address, address, uint256) public pure override {
        revert SoulBoundNFTCosigned__InvalidSignature();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert SoulBoundNFTCosigned__InvalidSignature();
    }

    /*///////////////////////////////////////////////////////////////
                                Soulbound Interface
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a token is locked
     * @return bool - True if the token is locked, false otherwise
     */
    function locked(uint256 /*tokenId*/) external pure returns (bool) {
        return true;
    }

    /*///////////////////////////////////////////////////////////////
                                View Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the domain separator for EIP-712
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Gets the current nonce for an address
     * @param account The address to query
     */
    function getNonce(address account) external view returns (uint256) {
        return nonces[account];
    }
}

