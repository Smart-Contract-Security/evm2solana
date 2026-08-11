// SPDX-License-Identifier: MIT

/*

    ASTRAFORGE NOMADS
    https://astraforgenomads.xyz
    https://x.com/astraforgeerc

*/

pragma solidity ^0.8.24;

interface IDN404Base {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function nftBalanceOf(address owner) external view returns (uint256);
    function nftOwnerOf(uint256 tokenId) external view returns (address);
    function nftGetApproved(uint256 tokenId) external view returns (address);
    function nftIsApprovedForAll(address owner, address operator) external view returns (bool);
    function nftTokenURI(uint256 tokenId) external view returns (string memory);
    function transferFromNFT(address from, address to, uint256 tokenId, address msgSender) external;
    function approveNFT(uint256 tokenId, address approved, address msgSender) external;
    function setApprovalForAllNFT(address operator, bool approved, address msgSender) external;
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract DN404Mirror {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    error MirrorAlreadyInitialized();
    error MirrorOnlyBase();
    error MirrorNotInitialized();
    error MirrorUnsafeRecipient();
    error MirrorUnauthorizedDeployer();

    address public base;
    address public immutable deployer;

    constructor(address _deployer) {
        deployer = _deployer;
    }

    function initFromBase() external {
        if (base != address(0)) revert MirrorAlreadyInitialized();
        if (tx.origin != deployer) revert MirrorUnauthorizedDeployer();
        base = msg.sender;
    }

    modifier onlyBase() {
        if (msg.sender != base) revert MirrorOnlyBase();
        _;
    }

    modifier whenInitialized() {
        if (base == address(0)) revert MirrorNotInitialized();
        _;
    }

    function emitTransferEvent(address from, address to, uint256 tokenId) external onlyBase {
        emit Transfer(from, to, tokenId);
    }

    function emitTransferBatch(address from, address to, uint256[] calldata tokenIds) external onlyBase {
        uint256 n = tokenIds.length;
        for (uint256 i; i < n; ) {
            emit Transfer(from, to, tokenIds[i]);
            unchecked { ++i; }
        }
    }

    function emitApprovalEvent(address owner, address approved, uint256 tokenId) external onlyBase {
        emit Approval(owner, approved, tokenId);
    }

    function emitApprovalForAllEvent(address owner, address operator, bool approved) external onlyBase {
        emit ApprovalForAll(owner, operator, approved);
    }

    function name() public view virtual whenInitialized returns (string memory) {
        return IDN404Base(base).name();
    }

    function symbol() public view virtual whenInitialized returns (string memory) {
        return IDN404Base(base).symbol();
    }

    function tokenURI(uint256 tokenId) external view whenInitialized returns (string memory) {
        return IDN404Base(base).nftTokenURI(tokenId);
    }

    function balanceOf(address owner) external view whenInitialized returns (uint256) {
        return IDN404Base(base).nftBalanceOf(owner);
    }

    function ownerOf(uint256 tokenId) external view whenInitialized returns (address) {
        return IDN404Base(base).nftOwnerOf(tokenId);
    }

    function getApproved(uint256 tokenId) external view whenInitialized returns (address) {
        return IDN404Base(base).nftGetApproved(tokenId);
    }

    function isApprovedForAll(address owner, address operator) external view whenInitialized returns (bool) {
        return IDN404Base(base).nftIsApprovedForAll(owner, operator);
    }

    function approve(address to, uint256 tokenId) external whenInitialized {
        IDN404Base(base).approveNFT(tokenId, to, msg.sender);
        address owner = IDN404Base(base).nftOwnerOf(tokenId);
        emit Approval(owner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external whenInitialized {
        IDN404Base(base).setApprovalForAllNFT(operator, approved, msg.sender);
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public whenInitialized {
        IDN404Base(base).transferFromNFT(from, to, tokenId, msg.sender);
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external whenInitialized {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external whenInitialized {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        if (to.code.length == 0) return;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 ret) {
            if (ret != IERC721Receiver.onERC721Received.selector) revert MirrorUnsafeRecipient();
        } catch {
            revert MirrorUnsafeRecipient();
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x5b5e139f;
    }
}
