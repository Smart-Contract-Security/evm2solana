// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import "../library/Ownable.sol";
import "./DaemonRenderer.sol";
import "./IDaemonRenderer.sol";
import "./IDaemonToken.sol";

struct FrozenDaemonClaim {
    uint256 seed;
    uint256 traitWord;
    uint256 originSwapBlock;
    uint256 wrappedBlock;
    bytes32 poolId;
    bytes32 corruptionState;
    uint64 corruptionEpoch;
    uint8 tier;
    uint256 burnedForUpgrade;
}

/// @notice ERC721 wrapper backed 1:1 by escrowed DAEMONS ERC20 artifacts.
contract DaemonWrapper is ERC721Enumerable, ReentrancyGuard, Ownable {
    error NotTokenOwnerOrApproved();
    error InvalidAddress();
    error InvalidUpgradeTier();
    error UpgradeNotIncreasing();
    error InvalidSacrificeCount();
    error ClaimNotFound();
    error MaxSupplyExceeded();

    uint256 private constant MAX_SUPPLY = 6_666;
    uint8 private constant TIER_1 = 1;
    uint8 private constant TIER_5X = 5;
    uint8 private constant TIER_10X = 10;
    uint256 private constant TIER_5X_BURN = 4;
    uint256 private constant TIER_10X_BURN = 9;
    uint256 private constant ROYALTY_BPS = 100;
    uint256 private constant ROYALTY_DENOMINATOR = 10_000;
    bytes4 private constant ERC4906_INTERFACE_ID = 0x49064906;
    bytes4 private constant ERC2981_INTERFACE_ID = 0x2a55205a;

    address public immutable daemon;
    address public immutable renderer;

    mapping(uint256 tokenId => uint256 seed) public tokenSeed;
    mapping(uint256 tokenId => FrozenDaemonClaim claim) public claims;

    event DaemonWrapped(uint256 indexed tokenId, uint256 indexed objectId, uint256 indexed requestId, address owner);
    event DaemonRedeemed(uint256 indexed tokenId, uint256 indexed objectId, address indexed redeemer);
    event DaemonRedeemedWithFee(
        uint256 indexed tokenId,
        uint256 indexed retiredObjectId,
        address indexed redeemer,
        uint256 payoutAmount,
        uint256 feeAmount,
        uint256 spawnedObjectId
    );
    event DaemonUpgraded(uint256 indexed tokenId, uint8 indexed tier, uint256 objectsBurnedForUpgrade);
    event DaemonAnimationRequested(uint256 indexed tokenId, uint8 indexed tier);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    constructor(address daemon_, address renderer_) ERC721("DAEMONS", "DAEMON") Ownable() {
        if (daemon_ == address(0) || renderer_ == address(0)) revert InvalidAddress();
        daemon = daemon_;
        renderer = renderer_;
    }

    function enabled() external pure returns (bool) {
        return true;
    }

    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function contractURI() external pure returns (string memory) {
        return 'data:application/json;utf8,{"name":"DAEMONS","description":"DAEMONS wrapped ERC721 collection. Each NFT is backed 1:1 by a DAEMON ERC20 artifact, with on-chain SVG metadata and burn upgrades.","external_link":"https://daemons.life","seller_fee_basis_points":100}';
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        receiver = _owner;
        royaltyAmount = (salePrice * ROYALTY_BPS) / ROYALTY_DENOMINATOR;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || interfaceId == ERC2981_INTERFACE_ID
            || super.supportsInterface(interfaceId);
    }

    function wrap(uint256 objectId) external nonReentrant returns (uint256 tokenId) {
        if (totalSupply() >= MAX_SUPPLY) revert MaxSupplyExceeded();

        uint256 seed = IDaemonToken(daemon).objectSeed(objectId);
        uint256 traitWord = IDaemonToken(daemon).objectTraitWord(objectId);
        uint256 originSwapBlock = IDaemonToken(daemon).objectOriginSwapBlock(objectId);
        (bytes32 poolId, bytes32 state, uint64 epoch) = IDaemonToken(daemon).currentCorruptionSnapshot();

        IDaemonToken(daemon).transferDmnFrom(msg.sender, address(this), objectId);

        tokenId = objectId;
        _storeClaim(tokenId, seed, traitWord, originSwapBlock, poolId, state, epoch);
        _safeMint(msg.sender, tokenId);
        emit DaemonWrapped(tokenId, objectId, 0, msg.sender);
        emit MetadataUpdate(tokenId);
    }

    function upgrade(uint256 tokenId, uint8 targetTier, uint256[] calldata sacrificeObjectIds) external nonReentrant {
        address tokenOwner = ownerOf(tokenId);
        if (tokenOwner != msg.sender) revert NotTokenOwnerOrApproved();
        if (targetTier != TIER_5X && targetTier != TIER_10X) revert InvalidUpgradeTier();

        FrozenDaemonClaim storage claim = claims[tokenId];
        if (claim.seed == 0) revert ClaimNotFound();
        if (claim.tier >= targetTier) revert UpgradeNotIncreasing();

        uint256 targetBurn = targetTier == TIER_5X ? TIER_5X_BURN : TIER_10X_BURN;
        uint256 burnCount = targetBurn - claim.burnedForUpgrade;
        if (sacrificeObjectIds.length != burnCount) revert InvalidSacrificeCount();

        IDaemonToken(daemon).sacrificeObjectsForUpgrade(tokenOwner, sacrificeObjectIds);
        claim.burnedForUpgrade = targetBurn;
        claim.tier = targetTier;

        emit DaemonUpgraded(tokenId, targetTier, targetBurn);
        if (targetTier == TIER_10X) emit DaemonAnimationRequested(tokenId, targetTier);
        emit MetadataUpdate(tokenId);
    }

    function redeem(uint256 tokenId) external nonReentrant {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner) revert NotTokenOwnerOrApproved();

        uint256 seed = tokenSeed[tokenId];
        if (seed == 0) revert ClaimNotFound();

        delete tokenSeed[tokenId];
        delete claims[tokenId];

        _burn(tokenId);
        (uint256 payoutAmount, uint256 feeAmount, uint256 spawnedObjectId) =
            IDaemonToken(daemon).redeemWrappedObject(tokenOwner, tokenId);

        emit DaemonRedeemed(tokenId, tokenId, tokenOwner);
        emit DaemonRedeemedWithFee(tokenId, tokenId, tokenOwner, payoutAmount, feeAmount, spawnedObjectId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert InvalidAddress();
        FrozenDaemonClaim memory claim = claims[tokenId];
        if (claim.seed == 0) revert ClaimNotFound();

        return IDaemonRenderer(renderer)
            .tokenURI(
                DaemonRenderRequest({
                    objectId: tokenId,
                    originSwapBlock: claim.originSwapBlock,
                    seed: claim.seed,
                    traitWord: claim.traitWord,
                    corruptionState: claim.corruptionState,
                    poolId: claim.poolId,
                    corruptionEpoch: claim.corruptionEpoch,
                    tier: claim.tier,
                    frozen: true
                })
            );
    }

    function _storeClaim(
        uint256 tokenId,
        uint256 seed,
        uint256 traitWord,
        uint256 originSwapBlock,
        bytes32 poolId,
        bytes32 state,
        uint64 epoch
    ) private {
        tokenSeed[tokenId] = seed;
        claims[tokenId] = FrozenDaemonClaim({
            seed: seed,
            traitWord: traitWord,
            originSwapBlock: originSwapBlock,
            wrappedBlock: block.number,
            poolId: poolId,
            corruptionState: state,
            corruptionEpoch: epoch,
            tier: TIER_1,
            burnedForUpgrade: 0
        });
    }
}
