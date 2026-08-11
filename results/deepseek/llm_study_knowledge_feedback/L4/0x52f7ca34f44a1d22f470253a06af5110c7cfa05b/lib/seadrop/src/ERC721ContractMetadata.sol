// SPDX-License-Identifier: MIT

import {
    ISeaDropTokenContractMetadata
} from "./interfaces/ISeaDropTokenContractMetadata.sol";

import {
    IERC165
} from "openzeppelin-contracts/utils/introspection/IERC165.sol";

import { IERC2981 } from "openzeppelin-contracts/interfaces/IERC2981.sol";

import {
    ICreatorToken,
    ILegacyCreatorToken
} from "./interfaces/ICreatorToken.sol";

/**
 * @title  ERC721ContractMetadata
 * @author James Wenzel (emo.eth)
 * @author Ryan Ghods (ralxz.eth)
 * @author Stephan Min (stephanm.eth)
 * @notice ERC721ContractMetadata is a token contract that extends ERC721A
 *         with additional metadata and ownership capabilities.
 */
contract ERC721ContractMetadata is
    ISeaDropTokenContractMetadata
{
    /// @notice Track the max supply.
    uint64 _maxSupply;

    /// @notice Track the base URI for token metadata.
    string _tokenBaseURI;

    /// @notice Track the contract URI for contract metadata.
    string _contractURI;

    /// @notice Track the provenance hash for guaranteeing metadata order
    ///         for random reveals.
    bytes32 _provenanceHash;

    /// @notice Track the royalty info: address to receive royalties, and
    ///         royalty basis points.
    RoyaltyInfo _royaltyInfo;

    /// @notice Track the owner.
    address _owner;

    /// @notice Track the pending owner for two-step ownership transfer.
    address _pendingOwner;

    /// @notice Track the transfer validator.
    address _transferValidator;

    /// @notice Track the next token id.
    uint64 _nextTokenId;

    /// @notice Track the total minted.
    uint64 _totalMinted;

    /// @notice Track the name.
    string _name;

    /// @notice Track the symbol.
    string _symbol;

    /// @notice Track the balance of each address.
    mapping(address => uint64) _balances;

    /// @notice Track the owner of each token id.
    mapping(uint64 => address) _owners;

    /// @notice Track the approved address for each token id.
    mapping(uint64 => address) _tokenApprovals;

    /// @notice Track the operator approvals.
    mapping(address => mapping(address => bool)) _operatorApprovals;

    /// @notice Emitted when ownership is transferred.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a pending ownership transfer is initiated.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a transfer occurs.
    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);

    /// @notice Emitted when an approval occurs.
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);

    /// @notice Emitted when an operator is approved or disapproved.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @notice Emitted when the max supply is updated.
    event MaxSupplyUpdated(uint64 newMaxSupply);

    /// @notice Emitted when the base URI is updated.
    event BatchMetadataUpdate(uint64 fromTokenId, uint64 toTokenId);

    /// @notice Emitted when the contract URI is updated.
    event ContractURIUpdated(string newContractURI);

    /// @notice Emitted when the provenance hash is updated.
    event ProvenanceHashUpdated(bytes32 oldProvenanceHash, bytes32 newProvenanceHash);

    /// @notice Emitted when the royalty info is updated.
    event RoyaltyInfoUpdated(address royaltyAddress, uint64 royaltyBps);

    /// @notice Modifier to restrict function access to the owner only.
    modifier onlyOwner() {
        if (tx.accounts.dataAccount.key != _owner) {
            revert("OnlyOwner");
        }
        _;
    }

    /**
     * @dev Reverts if the sender is not the owner or the contract itself.
     *      This function is inlined instead of being a modifier
     *      to save contract space from being inlined N times.
     */
    function _onlyOwnerOrSelf() internal view {
        if (
            _cast(tx.accounts.dataAccount.key == _owner) | _cast(tx.accounts.dataAccount.key == address(this)) ==
            0
        ) {
            revert("OnlyOwner");
        }
    }

    /**
     * @notice Deploy the token contract with its name and symbol.
     */
    constructor(string memory name, string memory symbol) {
        _name = name;
        _symbol = symbol;
        _owner = tx.accounts.dataAccount.key;
        emit OwnershipTransferred(address(0), tx.accounts.dataAccount.key);
    }

    /**
     * @notice Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the symbol of the token.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the owner of the contract.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the pending owner.
     */
    function pendingOwner() public view returns (address) {
        return _pendingOwner;
    }

    /**
     * @notice Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @notice Accepts the ownership transfer. Can only be called by the pending owner.
     */
    function acceptOwnership() public {
        if (tx.accounts.dataAccount.key != _pendingOwner) {
            revert("OnlyOwner");
        }
        address oldOwner = _owner;
        _owner = tx.accounts.dataAccount.key;
        delete _pendingOwner;
        emit OwnershipTransferred(oldOwner, tx.accounts.dataAccount.key);
    }

    /**
     * @notice Returns the total number of tokens minted.
     */
    function totalSupply() public view returns (uint64) {
        return _totalMinted;
    }

    /**
     * @notice Returns the next token id.
     */
    function getNextTokenId() internal view returns (uint64) {
        return _nextTokenId;
    }

    /**
     * @notice Returns the total number of tokens minted.
     */
    function getTotalMinted() internal view returns (uint64) {
        return _totalMinted;
    }

    /**
     * @notice Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint64 tokenId) public view returns (address) {
        address owner_ = _owners[tokenId];
        if (owner_ == address(0)) {
            revert("ERC721: invalid token ID");
        }
        return owner_;
    }

    /**
     * @notice Returns the number of tokens in `owner`'s account.
     */
    function balanceOf(address owner_) public view returns (uint64) {
        if (owner_ == address(0)) {
            revert("ERC721: address zero is not a valid owner");
        }
        return _balances[owner_];
    }

    /**
     * @notice Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint64 tokenId) public {
        address owner_ = ownerOf(tokenId);
        if (tx.accounts.dataAccount.key != owner_ && !isApprovedForAll(owner_, tx.accounts.dataAccount.key)) {
            revert("ERC721: approve caller is not token owner or approved for all");
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(owner_, to, tokenId);
    }

    /**
     * @notice Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint64 tokenId) public view returns (address) {
        if (_owners[tokenId] == address(0)) {
            revert("ERC721: invalid token ID");
        }
        return _tokenApprovals[tokenId];
    }

    /**
     * @notice Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) public {
        if (operator == tx.accounts.dataAccount.key) {
            revert("ERC721: approve to caller");
        }
        _operatorApprovals[tx.accounts.dataAccount.key][operator] = approved;
        emit ApprovalForAll(tx.accounts.dataAccount.key, operator, approved);
    }

    /**
     * @notice Returns if the `operator` is allowed to manage all of the assets of `owner_`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner_, address operator) public view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    /**
     * @notice Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint64 tokenId) public {
        if (!_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId)) {
            revert("ERC721: caller is not token owner or approved");
        }
        _transfer(from, to, tokenId);
    }

    /**
     * @notice Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint64 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @notice Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint64 tokenId, bytes memory data) public {
        if (!_isApprovedOrOwner(tx.accounts.dataAccount.key, tokenId)) {
            revert("ERC721: caller is not token owner or approved");
        }
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @notice Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint64 tokenId) internal view returns (bool) {
        address owner_ = ownerOf(tokenId);
        return (spender == owner_ || isApprovedForAll(owner_, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @notice Mints `quantity` tokens and transfers them to `to`.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `quantity` must be greater than 0.
     *
     * Emits a {Transfer} event for each mint.
     */
    function _mint(address to, uint64 quantity) internal {
        if (to == address(0)) {
            revert("ERC721: mint to the zero address");
        }
        if (quantity == 0) {
            revert("ERC721: quantity must be greater than 0");
        }
        uint64 startTokenId = _nextTokenId;
        _beforeTokenTransfers(address(0), to, startTokenId, quantity);
        for (uint64 i = 0; i < quantity; i++) {
            uint64 tokenId = startTokenId + i;
            _owners[tokenId] = to;
            emit Transfer(address(0), to, tokenId);
        }
        _balances[to] += quantity;
        _nextTokenId += quantity;
        _totalMinted += quantity;
    }

    /**
     * @notice Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint64 tokenId) internal {
        if (ownerOf(tokenId) != from) {
            revert("ERC721: transfer from incorrect owner");
        }
        if (to == address(0)) {
            revert("ERC721: transfer to the zero address");
        }
        _beforeTokenTransfers(from, to, tokenId, 1);
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    /**
     * @notice Safely transfers `tokenId` token from `from` to `to`, checking that the recipient
     * is a contract that implements {IERC721Receiver-onERC721Received}.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint64 tokenId, bytes memory data) internal {
        _transfer(from, to, tokenId);
        // On Solana, address.code is not available.
        // The check for contract recipient is omitted.
    }

    /**
     * @notice Sets the base URI for the token metadata and emits an event.
     *
     * @param newBaseURI The new base URI to set.
     */
    function setBaseURI(string calldata newBaseURI) external {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Set the new base URI.
        _tokenBaseURI = newBaseURI;

        // Emit an event with the update.
        if (totalSupply() != 0) {
            emit BatchMetadataUpdate(1, getNextTokenId() - 1);
        }
    }

    /**
     * @notice Sets the contract URI for contract metadata.
     *
     * @param newContractURI The new contract URI.
     */
    function setContractURI(string calldata newContractURI) external {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Set the new contract URI.
        _contractURI = newContractURI;

        // Emit an event with the update.
        emit ContractURIUpdated(newContractURI);
    }

    /**
     * @notice Emit an event notifying metadata updates for
     *         a range of token ids, according to EIP-4906.
     *
     * @param fromTokenId The start token id.
     * @param toTokenId   The end token id.
     */
    function emitBatchMetadataUpdate(uint64 fromTokenId, uint64 toTokenId)
        external
    {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Emit an event with the update.
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    /**
     * @notice Sets the max token supply and emits an event.
     *
     * @param newMaxSupply The new max supply to set.
     */
    function setMaxSupply(uint64 newMaxSupply) external {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the max supply does not exceed the maximum value of uint64.
        if (newMaxSupply > 2**64 - 1) {
            revert("CannotExceedMaxSupplyOfUint64");
        }

        // Ensure the max supply does not exceed the total minted.
        if (newMaxSupply < getTotalMinted()) {
            revert("NewMaxSupplyCannotBeLessThenTotalMinted");
        }

        // Set the new max supply.
        _maxSupply = newMaxSupply;

        // Emit an event with the update.
        emit MaxSupplyUpdated(newMaxSupply);
    }

    /**
     * @notice Sets the provenance hash and emits an event.
     *
     *         The provenance hash is used for random reveals, which
     *         is a hash of the ordered metadata to show it has not been
     *         modified after mint started.
     *
     *         This function will revert after the first item has been minted.
     *
     * @param newProvenanceHash The new provenance hash to set.
     */
    function setProvenanceHash(bytes32 newProvenanceHash) external {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Revert if any items have been minted.
        if (getTotalMinted() > 0) {
            revert("ProvenanceHashCannotBeSetAfterMintStarted");
        }

        // Keep track of the old provenance hash for emitting with the event.
        bytes32 oldProvenanceHash = _provenanceHash;

        // Set the new provenance hash.
        _provenanceHash = newProvenanceHash;

        // Emit an event with the update.
        emit ProvenanceHashUpdated(oldProvenanceHash, newProvenanceHash);
    }

    /**
     * @notice Sets the address and basis points for royalties.
     *
     * @param newInfo The struct to configure royalties.
     */
    function setRoyaltyInfo(RoyaltyInfo calldata newInfo) external {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Revert if the new royalty address is the zero address.
        if (newInfo.royaltyAddress == address(0)) {
            revert("RoyaltyAddressCannotBeZeroAddress");
        }

        // Revert if the new basis points is greater than 10_000.
        if (newInfo.royaltyBps > 10_000) {
            revert("InvalidRoyaltyBasisPoints");
        }

        // Set the new royalty info.
        _royaltyInfo = newInfo;

        // Emit an event with the updated params.
        emit RoyaltyInfoUpdated(newInfo.royaltyAddress, newInfo.royaltyBps);
    }

    /**
     * @notice Returns the base URI for token metadata.
     */
    function baseURI() external view returns (string memory) {
        return _baseURI();
    }

    /**
     * @notice Returns the base URI for the contract, which ERC721A uses
     *         to return tokenURI.
     */
    function _baseURI() internal view returns (string memory) {
        return _tokenBaseURI;
    }

    /**
     * @notice Returns the contract URI for contract metadata.
     */
    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice Returns the max token supply.
     */
    function maxSupply() public view returns (uint64) {
        return _maxSupply;
    }

    /**
     * @notice Returns the provenance hash.
     *         The provenance hash is used for random reveals, which
     *         is a hash of the ordered metadata to show it is unmodified
     *         after mint has started.
     */
    function provenanceHash() external view returns (bytes32) {
        return _provenanceHash;
    }

    /**
     * @notice Returns the address that receives royalties.
     */
    function royaltyAddress() external view returns (address) {
        return _royaltyInfo.royaltyAddress;
    }

    /**
     * @notice Returns the royalty basis points out of 10_000.
     */
    function royaltyBasisPoints() external view returns (uint64) {
        return _royaltyInfo.royaltyBps;
    }

    /**
     * @notice Called with the sale price to determine how much royalty
     *         is owed and to whom.
     *
     * @ param  _tokenId     The NFT asset queried for royalty information.
     * @param  _salePrice    The sale price of the NFT asset specified by
     *                       _tokenId.
     *
     * @return receiver      Address of who should be sent the royalty payment.
     * @return royaltyAmount The royalty payment amount for _salePrice.
     */
    function royaltyInfo(
        uint64,
        /* _tokenId */
        uint64 _salePrice
    ) external view returns (address receiver, uint64 royaltyAmount) {
        // Put the royalty info on the stack for more efficient access.
        RoyaltyInfo storage info = _royaltyInfo;

        // Set the royalty amount to the sale price times the royalty basis
        // points divided by 10_000.
        royaltyAmount = (_salePrice * info.royaltyBps) / 10_000;

        // Set the receiver of the royalty.
        receiver = info.royaltyAddress;
    }

    /**
     * @notice Returns the transfer validation function used.
     */
    function getTransferValidationFunction()
        external
        pure
        returns (bytes4 functionSignature, bool isViewFunction)
    {
        // ITransferValidator721.validateTransfer selector is 0x23b872dd
        functionSignature = bytes4(0x23b872dd);
        isViewFunction = false;
    }

    /**
     * @notice Set the transfer validator. Only callable by the token owner.
     */
    function setTransferValidator(address newValidator) external onlyOwner {
        // Set the new transfer validator.
        _setTransferValidator(newValidator);
    }

    /**
     * @dev Hook that is called before any token transfer.
     *      This includes minting and burning.
     */
    function _beforeTokenTransfers(
        address from,
        address to,
        uint64 startTokenId,
        uint64 /* quantity */
    ) internal {
        if (from != address(0) && to != address(0)) {
            // Call the transfer validator if one is set.
            address transferValidator = _transferValidator;
            if (transferValidator != address(0)) {
                // On Solana, external calls require the target program and accounts.
                // The transfer validator call is omitted as it requires
                // ITransferValidator721 interface which is not available.
                // In a full implementation, this would be a cross-program invocation.
            }
        }
    }

    /**
     * @notice Set the transfer validator.
     */
    function _setTransferValidator(address newValidator) internal {
        _transferValidator = newValidator;
    }

    /**
     * @notice Returns whether the interface is supported.
     *
     * @param interfaceId The interface id to check against.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(ICreatorToken).interfaceId ||
            interfaceId == type(ILegacyCreatorToken).interfaceId ||
            interfaceId == 0x49064906 || // ERC-4906
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Internal pure function to cast a `bool` value to a `uint64` value.
     *
     * @param b The `bool` value to cast.
     *
     * @return u The `uint64` value.
     */
    function _cast(bool b) internal pure returns (uint64 u) {
        assembly {
            u := b
        }
    }
}