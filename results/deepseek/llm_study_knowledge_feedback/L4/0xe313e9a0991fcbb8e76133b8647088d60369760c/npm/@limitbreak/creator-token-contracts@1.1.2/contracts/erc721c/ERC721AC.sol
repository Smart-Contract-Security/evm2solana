// SPDX-License-Identifier: MIT

import {AccountMeta, AccountInfo} from 'solana';

/**
 * @title ERC721AC
 * @author Limit Break, Inc.
 * @notice Extends Azuki's ERC721-A implementation with Creator Token functionality, which
 *         allows the contract owner to update the transfer validation logic by managing a security policy in
 *         an external transfer validation security policy registry.  See {CreatorTokenTransferValidator}.
 */
contract ERC721AC {

    string private _name;
    string private _symbol;

    // ERC721A state variables
    mapping(uint64 => address) private _owners;
    mapping(address => uint64) private _balances;
    mapping(uint64 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    uint64 private _currentIndex;
    uint64 private _burnCounter;

    // CreatorTokenBase state variables
    address private _transferValidator;
    address private _owner;

    event Transfer(address indexed from, address indexed to, uint64 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint64 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TransferValidatorUpdated(address oldTransferValidator, address newTransferValidator);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _currentIndex = _startTokenId();
        _owner = tx.accounts.dataAccount.key;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function totalSupply() public view returns (uint64) {
        return _currentIndex - _burnCounter - _startTokenId();
    }

    function balanceOf(address owner) public view returns (uint64) {
        require(owner != address(0), "Balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint64 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Owner query for nonexistent token");
        return owner;
    }

    function _startTokenId() internal pure returns (uint64) {
        return 1;
    }

    function _exists(uint64 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x80ac58cd || // ERC721
               interfaceId == 0x5b5e139f || // ERC721Metadata
               interfaceId == 0x01ffc9a7;   // ERC165
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Caller is not the owner");
        _;
    }

    function setTransferValidator(address transferValidator_) external onlyOwner {
        emit TransferValidatorUpdated(_transferValidator, transferValidator_);
        _transferValidator = transferValidator_;
    }

    function getTransferValidator() public view returns (address) {
        return _transferValidator;
    }

    function _validateBeforeTransfer(address from, address to, uint64 tokenId) internal virtual {
        if (_transferValidator != address(0)) {
            // External call to transfer validator would go here
            // On Solana, this would require CPI with proper accounts
        }
    }

    function _validateAfterTransfer(address from, address to, uint64 tokenId) internal virtual {
        // Post-transfer validation logic
    }

    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    /// @dev Ties the erc721a _beforeTokenTransfers hook to more granular transfer validation logic
    function _beforeTokenTransfers(
        address from,
        address to,
        uint64 startTokenId,
        uint64 quantity
    ) internal virtual {
        for (uint64 i = 0; i < quantity;) {
            _validateBeforeTransfer(from, to, startTokenId + i);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Ties the erc721a _afterTokenTransfer hook to more granular transfer validation logic
    function _afterTokenTransfers(
        address from,
        address to,
        uint64 startTokenId,
        uint64 quantity
    ) internal virtual {
        for (uint64 i = 0; i < quantity;) {
            _validateAfterTransfer(from, to, startTokenId + i);
            unchecked {
                ++i;
            }
        }
    }

    function _msgSenderERC721A() internal view returns (address) {
        return _msgSender();
    }

    function approve(address to, uint64 tokenId) public {
        address owner = ownerOf(tokenId);
        require(to != owner, "Approval to current owner");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()), "Not approved");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint64 tokenId) public view returns (address) {
        require(_exists(tokenId), "Approved query for nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        require(operator != _msgSender(), "Approve to caller");
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint64 tokenId) public {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Not approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint64 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint64 tokenId, bytes memory _data) public {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Not approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(address from, address to, uint64 tokenId, bytes memory _data) internal {
        _transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint64 tokenId) internal {
        require(ownerOf(tokenId) == from, "Transfer from incorrect owner");
        require(to != address(0), "Transfer to zero address");

        _beforeTokenTransfers(from, to, tokenId, 1);

        delete _tokenApprovals[tokenId];

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfers(from, to, tokenId, 1);
    }

    function _isApprovedOrOwner(address spender, uint64 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "Operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _mint(address to, uint64 quantity) internal {
        require(to != address(0), "Mint to zero address");
        require(quantity > 0, "Quantity must be greater than 0");

        uint64 startTokenId = _currentIndex;

        _beforeTokenTransfers(address(0), to, startTokenId, quantity);

        _balances[to] += quantity;
        _owners[startTokenId] = to;

        for (uint64 i = 1; i < quantity;) {
            emit Transfer(address(0), to, startTokenId + i);
            unchecked {
                ++i;
            }
        }

        _currentIndex += quantity;

        _afterTokenTransfers(address(0), to, startTokenId, quantity);
    }

    function _burn(uint64 tokenId) internal {
        address owner = ownerOf(tokenId);

        _beforeTokenTransfers(owner, address(0), tokenId, 1);

        delete _tokenApprovals[tokenId];
        _balances[owner] -= 1;
        delete _owners[tokenId];
        _burnCounter += 1;

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfers(owner, address(0), tokenId, 1);
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}