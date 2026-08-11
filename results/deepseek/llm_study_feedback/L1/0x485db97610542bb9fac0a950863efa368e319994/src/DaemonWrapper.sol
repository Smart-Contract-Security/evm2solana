// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract DaemonWrapper {
    uint256 public constant CONTRACT_REVISION = 5;

    bytes4 public constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 public constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 public constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;
    bytes4 public constant ERC721_RECEIVED = 0x150b7a02;

    address public immutable token;
    address public immutable renderer;

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

    // Custom errors replaced with string reverts for Solana compatibility
    // error NotOwner();
    // error NotApproved();
    // error ZeroAddress();
    // error TransferFailed();

    constructor(address daemonToken, address daemonRenderer) {
        if (daemonToken == address(0) || daemonRenderer == address(0)) revert("ZeroAddress");
        token = daemonToken;
        renderer = daemonRenderer;
    }

    function wrap() external returns (uint256 tokenId) {
        address sender = tx.accounts[0]; // msg.sender replacement
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, address(this), getEntityUnit())
        );
        if (!ok || (ret.length >= 32 && !abi.decode(ret, (bool)))) revert("TransferFailed");

        (bool ok2, bytes memory ret2) = token.call(
            abi.encodeWithSignature("getArtifactState(address)", sender)
        );
        if (!ok2) revert("TransferFailed");
        (uint256 state_corruption, uint256 state_aura, bytes32 state_seed) = abi.decode(ret2, (uint256, uint256, bytes32));

        tokenId = nextTokenId;
        nextTokenId = nextTokenId + 1;
        ownerOf[tokenId] = sender;
        balanceOf[sender] = balanceOf[sender] + 1;

        (bool ok3, bytes memory ret3) = token.call(
            abi.encodeWithSignature("deriveArtifactTraits(address,uint256)", sender, tokenId)
        );
        if (!ok3) revert("TransferFailed");
        uint256 traits = abi.decode(ret3, (uint256));

        snapshot[tokenId] = Snapshot({
            host: sender,
            traits: traits,
            corruption: state_corruption,
            aura: state_aura,
            seed: state_seed,
            frozenAt: block.timestamp
        });

        emit Transfer(address(0), sender, tokenId);
        emit Wrapped(sender, tokenId, state_seed);
    }

    function unwrap(uint256 tokenId) external {
        address sender = tx.accounts[0]; // msg.sender replacement
        if (ownerOf[tokenId] != sender) revert("NotOwner");

        delete ownerOf[tokenId];
        delete getApproved[tokenId];
        balanceOf[sender] = balanceOf[sender] - 1;

        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", sender, getEntityUnit())
        );
        if (!ok || (ret.length >= 32 && !abi.decode(ret, (bool)))) revert("TransferFailed");

        emit Transfer(sender, address(0), tokenId);
        emit Unwrapped(sender, tokenId);
    }

    function approve(address spender, uint256 tokenId) external {
        address sender = tx.accounts[0]; // msg.sender replacement
        address owner = ownerOf[tokenId];
        if (owner != sender && !isApprovedForAll[owner][sender]) revert("NotApproved");
        getApproved[tokenId] = spender;
        emit Approval(owner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        address sender = tx.accounts[0]; // msg.sender replacement
        isApprovedForAll[sender][operator] = approved;
        emit ApprovalForAll(sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address sender = tx.accounts[0]; // msg.sender replacement
        if (to == address(0)) revert("ZeroAddress");
        address owner = ownerOf[tokenId];
        if (owner != from) revert("NotOwner");
        if (sender != owner && sender != getApproved[tokenId] && !isApprovedForAll[owner][sender]) {
            revert("NotApproved");
        }

        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
        balanceOf[from] = balanceOf[from] - 1;
        balanceOf[to] = balanceOf[to] + 1;

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        // Use call with accounts provided for the receiver contract
        (bool ok, bytes memory ret) = to.call{accounts: [to]}(
            abi.encodeWithSignature("onERC721Received(address,address,uint256,bytes)", tx.accounts[0], from, tokenId, data)
        );
        if (ok && ret.length >= 32) {
            bytes4 response = abi.decode(ret, (bytes4));
            if (response != ERC721_RECEIVED) revert("TransferFailed");
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == ERC165_INTERFACE_ID || interfaceId == ERC721_INTERFACE_ID
            || interfaceId == ERC721_METADATA_INTERFACE_ID;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (ownerOf[tokenId] == address(0)) revert("NotOwner");
        Snapshot memory frozen = snapshot[tokenId];
        // Replace staticcall with call for Solana compatibility
        (bool ok, bytes memory ret) = renderer.call(
            abi.encodeWithSignature("tokenURI(uint256,address,uint256,uint256,uint256,bool)", tokenId, frozen.host, frozen.traits, frozen.corruption, frozen.aura, true)
        );
        if (!ok) revert("TransferFailed");
        return abi.decode(ret, (string));
    }

    function getEntityUnit() internal view returns (uint256) {
        // Replace staticcall with call for Solana compatibility
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSignature("ENTITY_UNIT()")
        );
        if (!ok) revert("TransferFailed");
        return abi.decode(ret, (uint256));
    }
}