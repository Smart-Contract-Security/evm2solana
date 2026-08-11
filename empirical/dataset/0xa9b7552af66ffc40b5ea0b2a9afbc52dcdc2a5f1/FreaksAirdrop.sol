// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title  FreaksAirdrop
/// @notice Upgradeable claim-based airdrop. Holds existing ERC-721 tokens (FREAKS V1/V2)
///         in escrow and lets eligible wallets claim one NFT each from a shared pool.
/// @dev    UUPS proxy. Reward logic for ETH / ERC-20 can be added in a future
///         implementation without redeploying the proxy (see __gap at the end).
///         we are all freaks — freaks.one
contract FreaksAirdrop is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IERC721Receiver
{
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice A single NFT sitting in the escrow pool.
    struct PoolItem {
        address collection; // ERC-721 contract (e.g. FREAKS V1 or V2)
        uint256 tokenId;
    }

    // ---------------------------------------------------------------------
    // Storage  (append-only across upgrades — never reorder/remove)
    // ---------------------------------------------------------------------

    /// @notice Available NFTs to be claimed. Claims pop from the tail (swap-and-pop).
    PoolItem[] private _pool;

    /// @notice On-chain allowlist. Eligible if true.
    mapping(address => bool) public allowlisted;

    /// @notice Off-chain allowlist root. Eligible if a valid proof is supplied.
    bytes32 public merkleRoot;

    /// @notice Tracks who already claimed. One claim per wallet, ever.
    mapping(address => bool) public hasClaimed;

    /// @notice When false, claiming is closed regardless of eligibility.
    bool public claimOpen;

    /// @notice When true, anyone can claim (ignores allowlist + merkle root).
    bool public publicClaim;

    /// @notice Wallets authorized to fund the pool besides the owner.
    ///         A depositor can only escrow NFTs it holds itself.
    mapping(address => bool) public isDepositor;

    /// @dev Reserved slots so future upgrades (ETH/ERC-20 rewards) can add
    ///      storage without colliding with inheriting layout. Decrement when used.
    uint256[39] private __gap;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event TokensDeposited(address indexed collection, uint256 count);
    event Claimed(address indexed wallet, address indexed collection, uint256 indexed tokenId);
    event AllowlistUpdated(address indexed wallet, bool allowed);
    event MerkleRootUpdated(bytes32 indexed root);
    event ClaimOpenSet(bool open);
    event PublicClaimSet(bool isPublic);
    event DepositorSet(address indexed wallet, bool allowed);
    event EmergencyWithdraw(address indexed collection, uint256 indexed tokenId, address indexed to);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ClaimClosed();
    error AlreadyClaimed();
    error NotEligible();
    error PoolEmpty();
    error LengthMismatch();
    error ZeroAddress();
    error NotAuthorized();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy. Call once, right after deployment.
    /// @param initialOwner address that controls the airdrop (transfer to multisig after).
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert ZeroAddress();
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __Pausable_init();
    }

    // ---------------------------------------------------------------------
    // Claiming
    // ---------------------------------------------------------------------

    /// @notice Claim one NFT from the pool. One per wallet.
    /// @param merkleProof proof for the merkle allowlist; pass an empty array
    ///        if you are on the on-chain allowlist or if publicClaim is on.
    function claim(bytes32[] calldata merkleProof) external nonReentrant whenNotPaused {
        if (!claimOpen) revert ClaimClosed();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (!_isEligible(msg.sender, merkleProof)) revert NotEligible();

        uint256 n = _pool.length;
        if (n == 0) revert PoolEmpty();

        // --- effects first (CEI + nonReentrant) ---
        hasClaimed[msg.sender] = true;
        PoolItem memory item = _pool[n - 1];
        _pool.pop();

        // --- interaction ---
        IERC721(item.collection).safeTransferFrom(address(this), msg.sender, item.tokenId);

        emit Claimed(msg.sender, item.collection, item.tokenId);
    }

    /// @notice Check eligibility without spending gas.
    function isEligible(address wallet, bytes32[] calldata merkleProof) external view returns (bool) {
        return _isEligible(wallet, merkleProof);
    }

    function _isEligible(address wallet, bytes32[] calldata merkleProof) internal view returns (bool) {
        if (publicClaim) return true;
        if (allowlisted[wallet]) return true;
        if (merkleRoot != bytes32(0)) {
            // OZ-recommended double-hashed leaf to resist second-preimage attacks.
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(wallet))));
            if (MerkleProof.verifyCalldata(merkleProof, merkleRoot, leaf)) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------------
    // Pool funding  (owner)
    // ---------------------------------------------------------------------

    /// @notice Load NFTs into the escrow pool. Callable by the owner or any
    ///         authorized depositor. The caller must hold the tokens and have
    ///         called setApprovalForAll(thisContract, true) on the collection first.
    /// @param collection the ERC-721 contract (FREAKS V1 or V2).
    /// @param tokenIds   token ids owned by the caller to escrow.
    function depositTokens(address collection, uint256[] calldata tokenIds) external {
        if (msg.sender != owner() && !isDepositor[msg.sender]) revert NotAuthorized();
        if (collection == address(0)) revert ZeroAddress();
        uint256 len = tokenIds.length;
        for (uint256 i; i < len; ) {
            IERC721(collection).transferFrom(msg.sender, address(this), tokenIds[i]);
            _pool.push(PoolItem({collection: collection, tokenId: tokenIds[i]}));
            unchecked { ++i; }
        }
        emit TokensDeposited(collection, len);
    }

    /// @notice Authorize (or revoke) a wallet to fund the pool via depositTokens.
    ///         Only affects who can deposit — a depositor can never withdraw or
    ///         change allowlists. The owner is always allowed.
    function setDepositor(address wallet, bool allowed) external onlyOwner {
        if (wallet == address(0)) revert ZeroAddress();
        isDepositor[wallet] = allowed;
        emit DepositorSet(wallet, allowed);
    }

    // ---------------------------------------------------------------------
    // Allowlist management  (owner)
    // ---------------------------------------------------------------------

    function setAllowlist(address[] calldata wallets, bool allowed) external onlyOwner {
        uint256 len = wallets.length;
        for (uint256 i; i < len; ) {
            allowlisted[wallets[i]] = allowed;
            emit AllowlistUpdated(wallets[i], allowed);
            unchecked { ++i; }
        }
    }

    function setMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
        emit MerkleRootUpdated(root);
    }

    // ---------------------------------------------------------------------
    // Toggles  (owner)
    // ---------------------------------------------------------------------

    function setClaimOpen(bool open) external onlyOwner {
        claimOpen = open;
        emit ClaimOpenSet(open);
    }

    function setPublicClaim(bool isPublic) external onlyOwner {
        publicClaim = isPublic;
        emit PublicClaimSet(isPublic);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---------------------------------------------------------------------
    // Emergency  (owner)
    // ---------------------------------------------------------------------

    /// @notice Pull an NFT back out of escrow. Does NOT touch hasClaimed.
    ///         Note: if the token is still in the pool, prefer pausing first.
    function emergencyWithdraw(address collection, uint256 tokenId, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
        emit EmergencyWithdraw(collection, tokenId, to);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice How many NFTs are left to claim.
    function poolSize() external view returns (uint256) {
        return _pool.length;
    }

    /// @notice Peek a slice of the pool (for dashboards). Use start/limit to paginate.
    function poolSlice(uint256 start, uint256 limit) external view returns (PoolItem[] memory items) {
        uint256 n = _pool.length;
        if (start >= n) return new PoolItem[](0);
        uint256 end = start + limit;
        if (end > n) end = n;
        items = new PoolItem[](end - start);
        for (uint256 i = start; i < end; ) {
            items[i - start] = _pool[i];
            unchecked { ++i; }
        }
    }

    // ---------------------------------------------------------------------
    // Hooks
    // ---------------------------------------------------------------------

    /// @notice Accept incoming ERC-721 transfers (so safeTransferFrom never reverts).
    ///         Tokens sent directly are NOT auto-added to the pool — always fund via
    ///         depositTokens() so the pool stays in sync.
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev UUPS upgrade authorization.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
