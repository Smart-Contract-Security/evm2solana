// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IDaemon {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function art() external view returns (address);
    function gate() external view returns (address);
}

interface IDaemonGate {
    function pulse(bytes32 poolId) external view returns (bytes32);
    function primaryPool() external view returns (bytes32);
}

interface IDaemonArt {
    function frozenURI(
        uint256 tokenId,
        bytes32 seed,
        bytes32 pulse,
        uint64  spawnBlock,
        bool    cleansed,
        bool    halo
    ) external view returns (string memory);
}

interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

contract DaemonHusk {
    string public constant name   = "DAEMON Husk";
    string public constant symbol = "hDAEMON";

    address public constant DEAD          = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant SEAL_AMOUNT   = 1 ether;
    uint256 public constant CLEANSE_BURN  = 4 ether;
    uint256 public constant ASCEND_BURN   = 9 ether;

    IDaemon public immutable core;

    struct Seal {
        bytes32 seed;
        bytes32 pulse;
        uint64  spawnBlock;
        bool    cleansed;
        bool    halo;
    }
    mapping(uint256 => Seal) public seals;

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    uint256 public totalSealed;
    uint256 public totalReleased;
    uint256 public totalUpgradeBurn;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Sealed(uint256 indexed tokenId, address indexed holder, bytes32 seed, bytes32 pulse, uint64 spawnBlock);
    event Released(uint256 indexed tokenId, address indexed holder);
    event Cleansed(uint256 indexed tokenId, address indexed holder);
    event Ascended(uint256 indexed tokenId, address indexed holder);

    error ZeroAddress();
    error NotOwner();
    error NotAuthorized();
    error TokenMissing();
    error AlreadyCleansed();
    error AlreadyHaloed();
    error MustCleanseFirst();
    error TransferFailed();
    error UnsafeReceiver();

    constructor(address _core) {
        if (_core == address(0)) revert ZeroAddress();
        core = IDaemon(_core);
    }

    function seal(uint256 slot) external returns (uint256 tokenId) {
        if (!core.transferFrom(msg.sender, address(this), SEAL_AMOUNT)) revert TransferFailed();

        bytes32 seed = keccak256(abi.encodePacked(msg.sender, slot, "DAEMON"));
        bytes32 p;
        address g = core.gate();
        if (g != address(0)) {
            bytes32 poolId = IDaemonGate(g).primaryPool();
            p = IDaemonGate(g).pulse(poolId);
        }

        unchecked { tokenId = ++totalSealed; }
        seals[tokenId] = Seal({
            seed:       seed,
            pulse:      p,
            spawnBlock: uint64(block.number),
            cleansed:   false,
            halo:       false
        });
        ownerOf[tokenId] = msg.sender;
        unchecked { balanceOf[msg.sender]++; }

        emit Transfer(address(0), msg.sender, tokenId);
        emit Sealed(tokenId, msg.sender, seed, p, uint64(block.number));
    }

    function release(uint256 tokenId) external {
        if (ownerOf[tokenId] != msg.sender) revert NotOwner();
        delete seals[tokenId];
        ownerOf[tokenId] = address(0);
        delete getApproved[tokenId];
        unchecked {
            balanceOf[msg.sender]--;
            totalReleased++;
        }
        if (!core.transfer(msg.sender, SEAL_AMOUNT)) revert TransferFailed();
        emit Transfer(msg.sender, address(0), tokenId);
        emit Released(tokenId, msg.sender);
    }

    function cleanse(uint256 tokenId) external {
        if (ownerOf[tokenId] != msg.sender) revert NotOwner();
        Seal storage s = seals[tokenId];
        if (s.cleansed) revert AlreadyCleansed();
        if (!core.transferFrom(msg.sender, DEAD, CLEANSE_BURN)) revert TransferFailed();
        s.cleansed = true;
        unchecked { totalUpgradeBurn += CLEANSE_BURN; }
        emit Cleansed(tokenId, msg.sender);
    }

    function ascend(uint256 tokenId) external {
        if (ownerOf[tokenId] != msg.sender) revert NotOwner();
        Seal storage s = seals[tokenId];
        if (!s.cleansed) revert MustCleanseFirst();
        if (s.halo) revert AlreadyHaloed();
        if (!core.transferFrom(msg.sender, DEAD, ASCEND_BURN)) revert TransferFailed();
        s.halo = true;
        unchecked { totalUpgradeBurn += ASCEND_BURN; }
        emit Ascended(tokenId, msg.sender);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (ownerOf[tokenId] == address(0)) revert TokenMissing();
        Seal memory s = seals[tokenId];
        address artAddr = core.art();
        if (artAddr == address(0)) return "";
        return IDaemonArt(artAddr).frozenURI(
            tokenId, s.seed, s.pulse, s.spawnBlock, s.cleansed, s.halo
        );
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf[tokenId];
        if (o == address(0)) revert TokenMissing();
        if (msg.sender != o && !isApprovedForAll[o][msg.sender]) revert NotAuthorized();
        getApproved[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert ZeroAddress();
        if (ownerOf[tokenId] != from) revert NotOwner();
        if (msg.sender != from
            && getApproved[tokenId] != msg.sender
            && !isApprovedForAll[from][msg.sender]) revert NotAuthorized();
        unchecked {
            balanceOf[from]--;
            balanceOf[to]++;
        }
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 r) {
                if (r != IERC721Receiver.onERC721Received.selector) revert UnsafeReceiver();
            } catch { revert UnsafeReceiver(); }
        }
    }

    function supportsInterface(bytes4 i) external pure returns (bool) {
        return i == 0x80ac58cd || i == 0x5b5e139f || i == 0x01ffc9a7;
    }
}
