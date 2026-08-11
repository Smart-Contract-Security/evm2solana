// SPDX-License-Identifier: MIT

import "./DaemonToken.sol";
import "./DaemonRenderer.sol";

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/**
 * @title DAEMONS Wrapper
 * @author DAEMONSv4
 * @notice ERC721 freeze adapter for DAEMON ERC20 artifacts
 *
 * Website: https://daemons.life
 * Twitter: https://x.com/DAEMONSv4
 *
 * Escrows 1 whole DAEMON, snapshots the holder's artifact state,
 * and mints a transferable ERC721 whose SVG/metadata are frozen
 * through the renderer. Unwrapping burns the frozen artifact and
 * returns the escrowed ERC20 backing.
 */

contract DaemonWrapper {
    uint256 public constant CONTRACT_REVISION = 5;

    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 public constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;
    bytes4 public constant ERC721_RECEIVED = 0x150b7a02;

    DaemonToken public immutable token;
    DaemonRenderer public immutable renderer;

    string public constant name = "Frozen DAEMONS";
    string public constant symbol = "fDAEMON";

    uint256 public nextTokenId = 1;
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(uint256 => Snapshot) public snapshot;

    struct Snapshot {
        address host;
        uint256 traits;
        uint256 corruption;
        uint256 aura;
        bytes32 seed;
        uint256 frozenAt;
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Wrapped(address indexed host, uint256 indexed tokenId, bytes32 seed);
    event Unwrapped(address indexed host, uint256 indexed tokenId);

    error NotOwner();
    error NotApproved();
    error ZeroAddress();
    error TransferFailed();

    constructor(DaemonToken daemonToken, DaemonRenderer daemonRenderer) {
        if (address(daemonToken) == address(0) || address(daemonRenderer) == address(0)) revert ZeroAddress();
        token = daemonToken;
        renderer = daemonRenderer;
    }

    function wrap() external returns (uint256 tokenId) {
        bool ok = token.transferFrom(tx.accounts.dataAccount.owner, address(this), token.ENTITY_UNIT());
        if (!ok) revert TransferFailed();

        DaemonToken.ArtifactState memory state = token.getArtifactState(tx.accounts.dataAccount.owner);
        tokenId = nextTokenId++;
        ownerOf[tokenId] = tx.accounts.dataAccount.owner;
        balanceOf[tx.accounts.dataAccount.owner]++;
        snapshot[tokenId] = Snapshot({
            host: tx.accounts.dataAccount.owner,
            traits: token.deriveArtifactTraits(tx.accounts.dataAccount.owner, tokenId),
            corruption: state.corruption,
            aura: state.aura,
            seed: state.seed,
            frozenAt: block.timestamp
        });

        emit Transfer(address(0), tx.accounts.dataAccount.owner, tokenId);
        emit Wrapped(tx.accounts.dataAccount.owner, tokenId, state.seed);
    }

    function unwrap(uint256 tokenId) external {
        if (ownerOf[tokenId] != tx.accounts.dataAccount.owner) revert NotOwner();

        delete ownerOf[tokenId];
        delete getApproved[tokenId];
        unchecked {
            balanceOf[tx.accounts.dataAccount.owner]--;
        }

        bool ok = token.transfer(tx.accounts.dataAccount.owner, token.ENTITY_UNIT());
        if (!ok) revert TransferFailed();

        emit Transfer(tx.accounts.dataAccount.owner, address(0), tokenId);
        emit Unwrapped(tx.accounts.dataAccount.owner, tokenId);
    }

    function approve(address spender, uint256 tokenId) external {
        address owner = ownerOf[tokenId];
        if (owner != tx.accounts.dataAccount.owner && !isApprovedForAll[owner][tx.accounts.dataAccount.owner]) revert NotApproved();
        getApproved[tokenId] = spender;
        emit Approval(owner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[tx.accounts.dataAccount.owner][operator] = approved;
        emit ApprovalForAll(tx.accounts.dataAccount.owner, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ZeroAddress();
        address owner = ownerOf[tokenId];
        if (owner != from) revert NotOwner();
        if (tx.accounts.dataAccount.owner != owner && tx.accounts.dataAccount.owner != getApproved[tokenId] && !isApprovedForAll[owner][tx.accounts.dataAccount.owner]) {
            revert NotApproved();
        }

        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
        unchecked {
            balanceOf[from]--;
            balanceOf[to]++;
        }

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            bytes4 response = IERC721Receiver(to).onERC721Received(tx.accounts.dataAccount.owner, from, tokenId, data);
            if (response != ERC721_RECEIVED) revert TransferFailed();
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID || interfaceId == ERC721_INTERFACE_ID
            || interfaceId == ERC721_METADATA_INTERFACE_ID;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (ownerOf[tokenId] == address(0)) revert NotOwner();
        Snapshot memory frozen = snapshot[tokenId];
        return renderer.tokenURI(tokenId, frozen.host, frozen.traits, frozen.corruption, frozen.aura, true);
    }
}