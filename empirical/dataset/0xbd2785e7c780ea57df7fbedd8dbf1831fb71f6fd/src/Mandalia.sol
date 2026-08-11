// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IRenderer {
    function render(bytes32 seed, uint16 transferCount, uint256 tokenId)
        external view returns (string memory);
}

interface IMandaliaStorage {
    function setSeed(uint256 tokenId, bytes32 seed) external;
    function incrementTransferCount(uint256 tokenId) external;
    function seedOf(uint256 tokenId) external view returns (bytes32);
    function transferCountOf(uint256 tokenId) external view returns (uint16);
}

/// @title Mandalia — fully onchain generative SVG NFT (10,000 supply, ETH L1)
/// @notice ERC-721 with dynamic SVG rendering. Royalties locked at 5% to dev wallet.
///         State-derived art: each transfer mutates the rendered output.
///         Spiritual successor to Heraldia (0x11A7E42036f8d039b0CE54b5488e3DF0Dff6cF36).
contract Mandalia is ERC721, ERC2981, IERC4906, Ownable, Pausable {

    // ============ Immutable Configuration ============
    uint256 public constant SUPPLY          = 10_000;
    uint256 public constant PRICE           = 0.0001 ether;
    uint256 public constant MAX_PER_TX      = 25;
    uint256 public constant MAX_PER_WALLET  = 25;
    uint256 public constant RESERVE         = 100;
    /// @notice Tiered free claim allowance for Heraldia holders:
    ///         1–4 held → 1 free · 5–9 held → 3 free · 10+ held → 10 free
    uint256 public constant HERALDIA_CAP    = 10;            // hard ceiling
    uint96  public constant ROYALTY_BPS     = 500;           // 5%
    address public constant DEV_WALLET      = 0x10A97F13F7737eb46113fa69B5Bd081c2ba797D0;
    /// @notice Heraldia contract — reference only; eligibility is enforced via the snapshot Merkle root, not live balance.
    address public constant HERALDIA_REF    = 0x11A7E42036F8D039b0ce54b5488E3df0dfF6Cf36;

    // ============ Storage ============
    IMandaliaStorage public immutable store;
    IRenderer public renderer;
    bool public rendererLocked;
    uint256 public startTime;
    uint256 public totalMinted;
    uint256 public reserveMinted;

    /// @notice Merkle root over leaves `keccak256(abi.encodePacked(holder, snapshotBalance))`.
    ///         Snapshot taken off-chain at a pre-announced block. Set by owner, optionally locked.
    bytes32 public heraldiaMerkleRoot;
    bool    public merkleLocked;

    mapping(address => uint256) public mintedPerWallet;
    mapping(address => uint256) public heraldiaClaimed;

    // ============ Errors ============
    error NotStarted();
    error SoldOut();
    error InvalidQty();
    error WalletCapExceeded();
    error WrongPayment();
    error PaymentFailed();
    error NotHeraldiaHolder();
    error ClaimExhausted();
    error ReserveExhausted();
    error RendererIsLocked();
    error MerkleIsLocked();
    error InvalidProof();
    error MerkleNotSet();
    error ZeroAddress();

    // ============ Constructor ============
    /// @param renderer_     Address of renderer contract (mutable until locked)
    /// @param storeContract Address of storage contract (immutable here, must be initialized to point back at this NFT)
    /// @param startTime_    Unix timestamp when mint opens (set 0 to open immediately)
    constructor(address renderer_, address storeContract, uint256 startTime_)
        ERC721("Mandalia", "MNDL")
        Ownable(msg.sender)
    {
        if (storeContract == address(0)) revert ZeroAddress();
        renderer  = IRenderer(renderer_);
        store     = IMandaliaStorage(storeContract);
        startTime = startTime_;
        _setDefaultRoyalty(DEV_WALLET, ROYALTY_BPS);
    }

    // ============ Public Mint ============

    /// @notice Paid mint to msg.sender
    function mint(uint256 qty) external payable whenNotPaused {
        _publicMint(msg.sender, qty);
    }

    /// @notice Paid mint to any address (use for gifting / airdrops — caller pays, `to` receives)
    function mintTo(address to, uint256 qty) external payable whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        _publicMint(to, qty);
    }

    /// @notice Free claim for Heraldia holders. Eligibility & balance proven via Merkle proof
    ///         against a pre-launch snapshot. Allowance = min(snapshotBalance, 10) per wallet.
    /// @param snapshotBalance The holder's Heraldia balance at snapshot block (must match leaf)
    /// @param proof Merkle proof for leaf = keccak256(abi.encodePacked(msg.sender, snapshotBalance))
    /// @param qty Quantity to claim in this tx
    function claimHeraldia(uint256 snapshotBalance, bytes32[] calldata proof, uint256 qty)
        external whenNotPaused
    {
        if (block.timestamp < startTime) revert NotStarted();
        if (qty == 0 || qty > MAX_PER_TX) revert InvalidQty();
        if (heraldiaMerkleRoot == bytes32(0)) revert MerkleNotSet();
        if (snapshotBalance == 0) revert NotHeraldiaHolder();

        // Verify (sender, balance) was in the snapshot
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, snapshotBalance));
        if (!MerkleProof.verify(proof, heraldiaMerkleRoot, leaf)) revert InvalidProof();

        uint256 allowance = _tieredAllowance(snapshotBalance);
        uint256 claimed   = heraldiaClaimed[msg.sender];
        if (claimed + qty > allowance) revert ClaimExhausted();

        uint256 walletTotal = mintedPerWallet[msg.sender] + qty;
        if (walletTotal > MAX_PER_WALLET) revert WalletCapExceeded();

        uint256 publicCap = SUPPLY - (RESERVE - reserveMinted);
        if (totalMinted + qty > publicCap) revert SoldOut();

        unchecked {
            heraldiaClaimed[msg.sender] = claimed + qty;
            mintedPerWallet[msg.sender] = walletTotal;
        }
        _mintMany(msg.sender, qty);
    }

    /// @dev Tiered free claim allowance based on Heraldia snapshot balance.
    ///      1–4 held → 1 free · 5–9 held → 3 free · 10+ held → 10 free.
    function _tieredAllowance(uint256 bal) internal pure returns (uint256) {
        if (bal >= 10) return 10;
        if (bal >= 5)  return 3;
        if (bal >= 1)  return 1;
        return 0;
    }

    // ============ Owner Mint ============

    /// @notice Free mint from dev reserve (max 100 total). Recipient can be any address.
    function mintReserve(address to, uint256 qty) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (qty == 0) revert InvalidQty();

        uint256 reserved = reserveMinted;
        if (reserved + qty > RESERVE) revert ReserveExhausted();

        uint256 walletTotal = mintedPerWallet[to] + qty;
        if (walletTotal > MAX_PER_WALLET) revert WalletCapExceeded();

        unchecked {
            reserveMinted = reserved + qty;
            mintedPerWallet[to] = walletTotal;
        }
        _mintMany(to, qty);
    }

    // ============ Internal Mint Logic ============

    function _publicMint(address to, uint256 qty) internal {
        if (block.timestamp < startTime) revert NotStarted();
        if (qty == 0 || qty > MAX_PER_TX) revert InvalidQty();
        if (msg.value != qty * PRICE) revert WrongPayment();

        uint256 walletTotal = mintedPerWallet[to] + qty;
        if (walletTotal > MAX_PER_WALLET) revert WalletCapExceeded();

        uint256 publicCap = SUPPLY - (RESERVE - reserveMinted);
        if (totalMinted + qty > publicCap) revert SoldOut();

        unchecked {
            mintedPerWallet[to] = walletTotal;
        }
        _mintMany(to, qty);

        // Forward ETH directly to dev wallet — no balance accumulates in contract
        (bool ok, ) = DEV_WALLET.call{value: msg.value}("");
        if (!ok) revert PaymentFailed();
    }

    function _mintMany(address to, uint256 qty) internal {
        uint256 startId = totalMinted + 1;
        unchecked {
            totalMinted += qty;
        }
        for (uint256 i; i < qty; ) {
            uint256 tokenId = startId + i;
            // Seed: prevrandao + recipient + tokenId. Manipulable by validators, acceptable for art.
            bytes32 seed = keccak256(abi.encodePacked(block.prevrandao, to, tokenId));
            store.setSeed(tokenId, seed);
            _safeMint(to, tokenId);
            unchecked { ++i; }
        }
    }

    // ============ Transfer Hook (increments per-token counter, emits EIP-4906) ============

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = super._update(to, tokenId, auth);
        // Only count post-mint transfers (from != 0). Burns also incremented but ignored downstream.
        if (from != address(0) && to != address(0)) {
            store.incrementTransferCount(tokenId);
            emit MetadataUpdate(tokenId);
        }
        return from;
    }

    // ============ Metadata ============

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        bytes32 seed = store.seedOf(tokenId);
        uint16  txc  = store.transferCountOf(tokenId);
        return renderer.render(seed, txc, tokenId);
    }

    /// @notice OpenSea collection metadata. CC0 license.
    function contractURI() external pure returns (string memory) {
        return string(abi.encodePacked(
            "data:application/json;utf8,",
            '{"name":"Mandalia","description":"10,000 fully onchain generative mandalas. State-derived SVG. Spiritual successor to Heraldia. CC0.",',
            '"image":"","external_link":"","seller_fee_basis_points":500,"fee_recipient":"0x10A97F13F7737eb46113fa69B5Bd081c2ba797D0"}'
        ));
    }

    // ============ Admin ============

    function setStartTime(uint256 newStart) external onlyOwner {
        startTime = newStart;
    }

    function setRenderer(address newRenderer) external onlyOwner {
        if (rendererLocked) revert RendererIsLocked();
        renderer = IRenderer(newRenderer);
    }

    /// @notice Permanently locks the renderer at its current address. Irreversible.
    function lockRenderer() external onlyOwner {
        rendererLocked = true;
    }

    /// @notice Sets the Merkle root of the Heraldia snapshot. Can be updated until locked.
    function setHeraldiaMerkleRoot(bytes32 root) external onlyOwner {
        if (merkleLocked) revert MerkleIsLocked();
        heraldiaMerkleRoot = root;
    }

    /// @notice Permanently locks the Merkle root. Irreversible.
    function lockMerkle() external onlyOwner {
        merkleLocked = true;
    }

    function pause()   external onlyOwner { _pause();   }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Recovers any ETH accidentally sent to the contract (not via mint).
    function rescue() external onlyOwner {
        (bool ok, ) = DEV_WALLET.call{value: address(this).balance}("");
        if (!ok) revert PaymentFailed();
    }

    // ============ View Helpers ============

    /// @notice Remaining free claim allowance given a verified snapshot balance.
    ///         Tiered: 1–4 held → 1 · 5–9 held → 3 · 10+ held → 10.
    function heraldiaAllowance(address holder, uint256 snapshotBalance) external view returns (uint256) {
        uint256 allow = _tieredAllowance(snapshotBalance);
        uint256 claimed = heraldiaClaimed[holder];
        return claimed >= allow ? 0 : allow - claimed;
    }

    function remainingPublicSupply() external view returns (uint256) {
        uint256 publicCap = SUPPLY - (RESERVE - reserveMinted);
        return publicCap - totalMinted;
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC2981, IERC165)
        returns (bool)
    {
        // 0x49064906 = IERC4906
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
    }
}
