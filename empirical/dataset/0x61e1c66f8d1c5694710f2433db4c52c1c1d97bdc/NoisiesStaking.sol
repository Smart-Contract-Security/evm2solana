// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

interface INoisiesNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract NoisiesStaking {
    address public owner;
    address public nft;

    uint256 public rewardRate = 10; // points per day
    uint256 public constant UPGRADE_COSTS_HAIR = 100;
    uint256 public constant UPGRADE_COSTS_ACC  = 80;
    uint256 public constant UPGRADE_COSTS_EXPR = 60;
    uint256 public constant MAX_LORE_LEN       = 280;
    uint256 public constant MAX_CHAPTERS       = 5;

    struct StakeInfo {
        uint256 stakedAt;
        uint256 claimedAt;
    }

    struct LoreData {
        string text;
        string[5] chapters;
        uint8 chapterCount;
        uint256 endorsements;
    }

    struct UpgradeData {
        uint8 hair;
        uint8 acc;
        uint8 expr;
        uint256 upgradeCount;
    }

    mapping(uint256 => StakeInfo)   public stakeInfo;
    mapping(uint256 => uint256)     public points;
    mapping(uint256 => LoreData)    public lore;
    mapping(uint256 => UpgradeData) public upgrades;
    mapping(uint256 => address)     public stakedBy;
    mapping(uint256 => bool)        public soulbound;

    uint256 public totalStaked;

    event Staked(uint256 indexed tokenId, address indexed staker);
    event Unstaked(uint256 indexed tokenId, address indexed staker);
    event RewardClaimed(uint256 indexed tokenId, uint256 amount);
    event LoreSet(uint256 indexed tokenId, string text);
    event ChapterAdded(uint256 indexed tokenId, uint8 chapterIdx);
    event LoreEndorsed(uint256 indexed tokenId, address endorser);
    event TraitUpgraded(uint256 indexed tokenId, string trait, uint8 newValue);
    event SoulboundSet(uint256 indexed tokenId, bool locked);

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    modifier onlyNFTOwner(uint256 tokenId) {
        require(INoisiesNFT(nft).ownerOf(tokenId) == msg.sender, "not token owner");
        _;
    }

    constructor(address _nft) { owner = msg.sender; nft = _nft; }

    function setNFT(address _nft) external onlyOwner { nft = _nft; }
    function setRewardRate(uint256 rate) external onlyOwner { rewardRate = rate; }

    // ── STAKING ───────────────────────────────────────────
    function stake(uint256 tokenId) external onlyNFTOwner(tokenId) {
        require(stakeInfo[tokenId].stakedAt == 0, "already staked");
        stakeInfo[tokenId] = StakeInfo(block.timestamp, block.timestamp);
        stakedBy[tokenId] = msg.sender;
        totalStaked++;
        emit Staked(tokenId, msg.sender);
    }

    function unstake(uint256 tokenId) external onlyNFTOwner(tokenId) {
        require(stakeInfo[tokenId].stakedAt > 0, "not staked");
        _accrue(tokenId);
        stakeInfo[tokenId].stakedAt = 0;
        stakeInfo[tokenId].claimedAt = 0;
        stakedBy[tokenId] = address(0);
        totalStaked--;
        emit Unstaked(tokenId, msg.sender);
    }

    function claimReward(uint256 tokenId) external onlyNFTOwner(tokenId) {
        require(stakeInfo[tokenId].stakedAt > 0, "not staked");
        uint256 earned = _accrue(tokenId);
        require(earned > 0, "nothing to claim");
        emit RewardClaimed(tokenId, earned);
    }

    function pendingReward(uint256 tokenId) external view returns (uint256) {
        if (stakeInfo[tokenId].stakedAt == 0) return 0;
        uint256 elapsed = block.timestamp - stakeInfo[tokenId].claimedAt;
        return (elapsed * rewardRate) / 1 days;
    }

    function isStaked(uint256 tokenId) external view returns (bool) {
        return stakeInfo[tokenId].stakedAt > 0;
    }

    function stakedSince(uint256 tokenId) external view returns (uint256) {
        return stakeInfo[tokenId].stakedAt;
    }

    function getPoints(uint256 tokenId) external view returns (uint256) {
        return points[tokenId];
    }

    function _accrue(uint256 tokenId) internal returns (uint256 earned) {
        uint256 elapsed = block.timestamp - stakeInfo[tokenId].claimedAt;
        earned = (elapsed * rewardRate) / 1 days;
        if (earned > 0) {
            points[tokenId] += earned;
            stakeInfo[tokenId].claimedAt = block.timestamp;
        }
    }

    // ── LORE ──────────────────────────────────────────────
    function setLore(uint256 tokenId, string calldata text) external onlyNFTOwner(tokenId) {
        require(bytes(text).length <= MAX_LORE_LEN, "lore too long");
        lore[tokenId].text = text;
        emit LoreSet(tokenId, text);
    }

    function addChapter(uint256 tokenId, string calldata text) external onlyNFTOwner(tokenId) {
        require(bytes(text).length <= MAX_LORE_LEN, "chapter too long");
        require(lore[tokenId].chapterCount < MAX_CHAPTERS, "max chapters");
        lore[tokenId].chapters[lore[tokenId].chapterCount] = text;
        emit ChapterAdded(tokenId, lore[tokenId].chapterCount);
        lore[tokenId].chapterCount++;
    }

    function endorseLore(uint256 tokenId) external {
        // open to all holders
        require(bytes(lore[tokenId].text).length > 0, "no lore");
        lore[tokenId].endorsements++;
        emit LoreEndorsed(tokenId, msg.sender);
    }

    function getLore(uint256 tokenId) external view returns (
        string memory text, uint8 chapterCount, uint256 endorsements
    ) {
        return (lore[tokenId].text, lore[tokenId].chapterCount, lore[tokenId].endorsements);
    }

    function getChapter(uint256 tokenId, uint8 idx) external view returns (string memory) {
        require(idx < lore[tokenId].chapterCount, "no chapter");
        return lore[tokenId].chapters[idx];
    }

    // ── UPGRADES ──────────────────────────────────────────
    function upgradeHair(uint256 tokenId, uint8 newStyle) external onlyNFTOwner(tokenId) {
        require(newStyle < 12, "invalid style");
        require(points[tokenId] >= UPGRADE_COSTS_HAIR, "insufficient points");
        points[tokenId] -= UPGRADE_COSTS_HAIR;
        upgrades[tokenId].hair = newStyle;
        upgrades[tokenId].upgradeCount++;
        emit TraitUpgraded(tokenId, "hair", newStyle);
    }

    function upgradeAcc(uint256 tokenId, uint8 newAcc) external onlyNFTOwner(tokenId) {
        require(newAcc < 14, "invalid acc");
        require(points[tokenId] >= UPGRADE_COSTS_ACC, "insufficient points");
        points[tokenId] -= UPGRADE_COSTS_ACC;
        upgrades[tokenId].acc = newAcc;
        upgrades[tokenId].upgradeCount++;
        emit TraitUpgraded(tokenId, "acc", newAcc);
    }

    function upgradeExpression(uint256 tokenId, uint8 newExpr) external onlyNFTOwner(tokenId) {
        require(newExpr < 6, "invalid expr");
        require(points[tokenId] >= UPGRADE_COSTS_EXPR, "insufficient points");
        points[tokenId] -= UPGRADE_COSTS_EXPR;
        upgrades[tokenId].expr = newExpr;
        upgrades[tokenId].upgradeCount++;
        emit TraitUpgraded(tokenId, "expr", newExpr);
    }

    function getUpgradeData(uint256 tokenId) external view returns (uint8 hair, uint8 acc, uint8 expr, uint256 count) {
        UpgradeData memory u = upgrades[tokenId];
        return (u.hair, u.acc, u.expr, u.upgradeCount);
    }

    function hasUpgrade(uint256 tokenId) external view returns (bool) {
        return upgrades[tokenId].upgradeCount > 0;
    }

    // ── SOULBOUND ─────────────────────────────────────────
    function setSoulbound(uint256 tokenId, bool locked) external onlyNFTOwner(tokenId) {
        soulbound[tokenId] = locked;
        emit SoulboundSet(tokenId, locked);
    }

    function isSoulbound(uint256 tokenId) external view returns (bool) {
        return soulbound[tokenId];
    }
}
