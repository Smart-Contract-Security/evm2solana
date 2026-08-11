// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IForgottenWorldsPass {
    function ownerOf(uint256 tokenId) external view returns (address);
    function canUseForPhase(
        uint256 passId,
        uint8 phaseId
    ) external view returns (bool);
    function markPassUsedForPhase(uint256 passId, uint8 phaseId) external;
    function mintPhaseOneRewardPass(address to) external;
    function mintPhaseTwoRewardPasses(address to) external;
}

interface IForgottenWorldsRenderer {
    function tokenURIForPhase(
        uint256 tokenId,
        uint8 phaseId
    ) external pure returns (string memory);
}

contract ForgottenWorldsNFT is
    ERC721,
    Ownable,
    ReentrancyGuard,
    Pausable
{
    uint256 public constant MAX_SUPPLY = 2000;

    uint256 public constant PHASE_ONE_SUPPLY = 1000;
    uint256 public constant PHASE_TWO_SUPPLY = 300;
    uint256 public constant PHASE_THREE_SUPPLY = 500;
    uint256 public constant PHASE_FOUR_SUPPLY = 200;

    uint8 public constant PHASE_ONE = 1;
    uint8 public constant PHASE_TWO = 2;
    uint8 public constant PHASE_THREE = 3;
    uint8 public constant PHASE_FOUR = 4;

    uint256 public constant PHASE_ONE_WINNER_COUNT = 400;

    uint8 public constant REWARD_NONE = 0;
    uint8 public constant REWARD_COMMON = 1;
    uint8 public constant REWARD_RARE = 2;
    uint8 public constant REWARD_SUPER_RARE = 3;

    uint256 public constant BURN_FEE_BPS = 1000; // 10%
    uint256 public constant BPS_DENOMINATOR = 10000;

    uint256 public constant FEE_PRECISION = 1e18;

    uint256 public constant TOTAL_SUPER_RARE_REWARDS = 10;
    uint256 public constant TOTAL_RARE_REWARDS = 20;

    IForgottenWorldsPass public passContract;
    IForgottenWorldsRenderer public renderer;

    uint256 public totalMinted;

    uint256 public phaseOneMinted;
    uint256 public phaseTwoMinted;
    uint256 public phaseThreeMinted;
    uint256 public phaseFourMinted;

    uint256 public phaseOnePrice;
    uint256 public phaseTwoPrice;
    uint256 public phaseThreePrice;
    uint256 public phaseFourPrice;

    bool public phaseOneRewardsFinalized;
    uint256 public phaseOneRewardSeed;
    uint256 public phaseOneRewardSelected;

    uint256 public commonRewardAmount;
    uint256 public rareRewardAmount;
    uint256 public superRareRewardAmount;

    uint256 public mintRevenue;
    uint256 public rewardPoolFunded;
    uint256 public burnFeesCollected;

    uint256 public accFeePerShare;
    uint256 public totalFeeShareReceived;
    uint256 public activeShareSupply;

    uint256 public totalSuperRareAssigned;
    uint256 public totalRareAssigned;

    uint256 public finalRareBonusAmount;
    uint256 public finalSuperRareBonusAmount;

    uint256 public rareRemaining;
    uint256 public superRareRemaining;

    bool public rewardCountsLocked;

    mapping(uint256 => uint256) public feeDebt;

    uint8 public activePhase;

    mapping(uint8 => mapping(address => uint256)) public mintedPerPhase;
    mapping(uint256 => uint8) public tokenPhase;
    mapping(uint256 => uint64) public tokenSeed;

    mapping(address => bool) public isPhaseOneMinter;
    address[] public phaseOneMinters;

    mapping(address => bool) public phaseTwoRewardGiven;

    mapping(address => bool) public phaseOneRewardWinner;
    mapping(uint256 => uint256) private phaseOneSelectionSwap;

    mapping(uint256 => uint8) public rewardTier;
    mapping(uint256 => bool) public burnedForReward;

    mapping(uint8 => uint256) public phaseSuperRareAssigned;
    mapping(uint8 => uint256) public phaseRareAssigned;

    event PhaseUpdated(uint8 phase);
    event PhasePriceUpdated(uint8 phase, uint256 price);
    event WorldMinted(
        address indexed minter,
        uint256 indexed tokenId,
        uint8 phase
    );

    event PhaseOneRewardSeedSet(uint256 seed);
    event PhaseOneRewardWinnerSelected(
        address indexed winner,
        uint256 rewardPassId
    );

    event RewardTierSet(uint256 indexed tokenId, uint8 tier);
    event RewardAmountsUpdated(
        uint256 commonAmount,
        uint256 rareAmount,
        uint256 superRareAmount
    );
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event MintRevenueWithdrawn(address indexed receiver, uint256 amount);
    event NFTBurnedForReward(
        uint256 indexed tokenId,
        address indexed owner,
        uint8 tier,
        uint256 gross,
        uint256 fee,
        uint256 net
    );

    event FinalRewardAmountsUpdated(
        uint256 finalRareAmount,
        uint256 finalSuperRareAmount
    );
    event RewardCountsLocked(uint256 rareRemaining, uint256 superRareRemaining);

    constructor(
        address _passContract,
        address _renderer
    ) ERC721("Forgotten Worlds", "FWORLD") Ownable(msg.sender) {
        require(_passContract != address(0), "Invalid pass");
        require(_renderer != address(0), "Invalid renderer");

        passContract = IForgottenWorldsPass(_passContract);
        renderer = IForgottenWorldsRenderer(_renderer);
    }

    receive() external payable {
        rewardPoolFunded += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value);
    }

    //--------------------------
    // Helper Functions
    //--------------------------

    function _selectionValue(uint256 index) internal view returns (uint256) {
        uint256 value = phaseOneSelectionSwap[index];
        return value == 0 ? index : value - 1;
    }

    function getPhaseOneMinter(uint256 index) external view returns (address) {
        return phaseOneMinters[index];
    }

    function rewardAmountForTier(uint8 tier) public view returns (uint256) {
        if (tier == REWARD_COMMON) return commonRewardAmount;
        if (tier == REWARD_RARE) return rareRewardAmount;
        if (tier == REWARD_SUPER_RARE) return superRareRewardAmount;
        return 0;
    }

    function pendingMarketplaceFees(
        uint256 tokenId
    ) external view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        return (accFeePerShare - feeDebt[tokenId]) / FEE_PRECISION;
    }

    function phaseSuperRareQuota(uint8 phase) public pure returns (uint256) {
        if (phase == PHASE_ONE) return 1;
        if (phase == PHASE_TWO) return 2;
        if (phase == PHASE_THREE) return 4;
        if (phase == PHASE_FOUR) return 3;
        return 0;
    }

    function phaseRareQuota(uint8 phase) public pure returns (uint256) {
        if (phase == PHASE_ONE) return 3;
        if (phase == PHASE_TWO) return 4;
        if (phase == PHASE_THREE) return 8;
        if (phase == PHASE_FOUR) return 5;
        return 0;
    }

    function _rewardAmountForBurn(uint8 tier) internal view returns (uint256) {
        if (tier == REWARD_COMMON) {
            return commonRewardAmount;
        }

        if (tier == REWARD_RARE) {
            if (rewardCountsLocked && rareRemaining == 1) {
                return finalRareBonusAmount;
            }

            return rareRewardAmount;
        }

        if (tier == REWARD_SUPER_RARE) {
            if (rewardCountsLocked && superRareRemaining == 1) {
                return finalSuperRareBonusAmount;
            }

            return superRareRewardAmount;
        }

        return 0;
    }

    // -------------------------
    // Internal
    // -------------------------

    function _setRewardTierInternal(uint256 tokenId, uint8 tier) internal {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(tier <= REWARD_SUPER_RARE, "Invalid tier");
        require(rewardTier[tokenId] == REWARD_NONE, "Reward already set");

        uint8 phase = tokenPhase[tokenId];

        if (tier == REWARD_SUPER_RARE) {
            require(
                totalSuperRareAssigned < TOTAL_SUPER_RARE_REWARDS,
                "Super rare total exceeded"
            );
            require(
                phaseSuperRareAssigned[phase] < phaseSuperRareQuota(phase),
                "Super rare phase quota exceeded"
            );

            totalSuperRareAssigned++;
            phaseSuperRareAssigned[phase]++;
        }

        if (tier == REWARD_RARE) {
            require(
                totalRareAssigned < TOTAL_RARE_REWARDS,
                "Rare total exceeded"
            );
            require(
                phaseRareAssigned[phase] < phaseRareQuota(phase),
                "Rare phase quota exceeded"
            );

            totalRareAssigned++;
            phaseRareAssigned[phase]++;
        }

        rewardTier[tokenId] = tier;

        emit RewardTierSet(tokenId, tier);
    }

    // -------------------------
    // Admin
    // -------------------------

    function setActivePhase(uint8 phase) external onlyOwner {
        require(phase <= PHASE_FOUR, "Invalid phase");
        activePhase = phase;
        emit PhaseUpdated(phase);
    }

    function setRenderer(address _renderer) external onlyOwner {
        require(_renderer != address(0), "Invalid renderer");
        renderer = IForgottenWorldsRenderer(_renderer);
    }

    function setPhasePrice(uint8 phase, uint256 price) external onlyOwner {
        require(phase >= PHASE_ONE && phase <= PHASE_FOUR, "Invalid phase");

        if (phase == PHASE_ONE) phaseOnePrice = price;
        else if (phase == PHASE_TWO) phaseTwoPrice = price;
        else if (phase == PHASE_THREE) phaseThreePrice = price;
        else phaseFourPrice = price;

        emit PhasePriceUpdated(phase, price);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawMintRevenue(address payable to) external onlyOwner {
        require(to != address(0), "Invalid receiver");

        uint256 amount = mintRevenue;
        mintRevenue = 0;

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");

        emit MintRevenueWithdrawn(to, amount);
    }

    function setRewardAmounts(
        uint256 _commonRewardAmount,
        uint256 _rareRewardAmount,
        uint256 _superRareRewardAmount
    ) external onlyOwner {
        commonRewardAmount = _commonRewardAmount;
        rareRewardAmount = _rareRewardAmount;
        superRareRewardAmount = _superRareRewardAmount;

        emit RewardAmountsUpdated(
            _commonRewardAmount,
            _rareRewardAmount,
            _superRareRewardAmount
        );
    }

    function setRewardTier(uint256 tokenId, uint8 tier) external onlyOwner {
        _setRewardTierInternal(tokenId, tier);
    }

    function setRewardTiers(
        uint256[] calldata tokenIds,
        uint8[] calldata tiers
    ) external onlyOwner {
        require(tokenIds.length == tiers.length, "Length mismatch");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _setRewardTierInternal(tokenIds[i], tiers[i]);
        }
    }

    function fundRewardPool() external payable onlyOwner {
        require(msg.value > 0, "No ETH sent");

        rewardPoolFunded += msg.value;

        emit RewardPoolFunded(msg.sender, msg.value);
    }

    function setFinalRewardAmounts(
        uint256 _finalRareBonusAmount,
        uint256 _finalSuperRareBonusAmount
    ) external onlyOwner {
        finalRareBonusAmount = _finalRareBonusAmount;
        finalSuperRareBonusAmount = _finalSuperRareBonusAmount;

        emit FinalRewardAmountsUpdated(
            _finalRareBonusAmount,
            _finalSuperRareBonusAmount
        );
    }

    function lockRewardCounts() external onlyOwner {
        require(!rewardCountsLocked, "Already locked");
        require(
            totalRareAssigned > 0 || totalSuperRareAssigned > 0,
            "No rewards assigned"
        );

        rareRemaining = totalRareAssigned;
        superRareRemaining = totalSuperRareAssigned;
        rewardCountsLocked = true;

        emit RewardCountsLocked(rareRemaining, superRareRemaining);
    }

    // -------------------------
    // Phase 1 Mint
    // -------------------------

    function mintPhaseOne(
        uint256 quantity,
        uint256 passId
    ) external payable nonReentrant whenNotPaused {
        require(activePhase == PHASE_ONE, "Phase 1 inactive");
        require(quantity > 0 && quantity <= 3, "Invalid quantity");
        require(
            mintedPerPhase[PHASE_ONE][msg.sender] + quantity <= 3,
            "Phase 1 wallet cap"
        );
        require(
            phaseOneMinted + quantity <= PHASE_ONE_SUPPLY,
            "Phase 1 sold out"
        );
        require(msg.value == phaseOnePrice * quantity, "Wrong ETH");

        require(passContract.ownerOf(passId) == msg.sender, "Not pass owner");
        require(
            passContract.canUseForPhase(passId, PHASE_ONE),
            "Pass not valid"
        );

        mintRevenue += msg.value;

        if (!isPhaseOneMinter[msg.sender]) {
            isPhaseOneMinter[msg.sender] = true;
            phaseOneMinters.push(msg.sender);
        }

        mintedPerPhase[PHASE_ONE][msg.sender] += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            phaseOneMinted++;
            _mintWorld(msg.sender, PHASE_ONE);
        }
    }

    function finalizePhaseOneRewards() external onlyOwner {
        require(!phaseOneRewardsFinalized, "Already finalized");
        require(activePhase != PHASE_ONE, "Phase 1 still active");
        require(
            phaseOneMinters.length >= PHASE_ONE_WINNER_COUNT,
            "Not enough minters"
        );

        phaseOneRewardsFinalized = true;

        phaseOneRewardSeed = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    blockhash(block.number - 1),
                    phaseOneMinted,
                    phaseOneMinters.length,
                    address(this)
                )
            )
        );

        emit PhaseOneRewardSeedSet(phaseOneRewardSeed);
    }

    function selectPhaseOneRewardWinners(uint256 count) external onlyOwner {
        require(phaseOneRewardsFinalized, "Rewards not finalized");
        require(
            phaseOneRewardSelected < PHASE_ONE_WINNER_COUNT,
            "All winners selected"
        );

        uint256 remainingWinners = PHASE_ONE_WINNER_COUNT -
            phaseOneRewardSelected;
        if (count > remainingWinners) count = remainingWinners;

        uint256 minterCount = phaseOneMinters.length;

        for (uint256 i = 0; i < count; i++) {
            uint256 remaining = minterCount - phaseOneRewardSelected;

            uint256 randomIndex = uint256(
                keccak256(
                    abi.encodePacked(
                        phaseOneRewardSeed,
                        phaseOneRewardSelected,
                        i
                    )
                )
            ) % remaining;

            uint256 selectedIndex = _selectionValue(randomIndex);
            uint256 lastIndex = _selectionValue(remaining - 1);

            phaseOneSelectionSwap[randomIndex] = lastIndex + 1;

            address winner = phaseOneMinters[selectedIndex];

            require(!phaseOneRewardWinner[winner], "Duplicate winner");

            phaseOneRewardWinner[winner] = true;
            phaseOneRewardSelected++;

            passContract.mintPhaseOneRewardPass(winner);

            emit PhaseOneRewardWinnerSelected(winner, phaseOneRewardSelected);
        }
    }

    // -------------------------
    // Phase 2 Mint
    // -------------------------

    function mintPhaseTwo(
        uint256 quantity
    ) external payable nonReentrant whenNotPaused {
        require(activePhase == PHASE_TWO, "Phase 2 inactive");
        require(quantity > 0 && quantity <= 2, "Invalid quantity");
        require(
            mintedPerPhase[PHASE_TWO][msg.sender] + quantity <= 2,
            "Phase 2 wallet cap"
        );
        require(
            phaseTwoMinted + quantity <= PHASE_TWO_SUPPLY,
            "Phase 2 sold out"
        );
        require(msg.value == phaseTwoPrice * quantity, "Wrong ETH");

        mintRevenue += msg.value;
        mintedPerPhase[PHASE_TWO][msg.sender] += quantity;

        if (!phaseTwoRewardGiven[msg.sender]) {
            phaseTwoRewardGiven[msg.sender] = true;
            passContract.mintPhaseTwoRewardPasses(msg.sender);
        }

        for (uint256 i = 0; i < quantity; i++) {
            phaseTwoMinted++;
            _mintWorld(msg.sender, PHASE_TWO);
        }
    }

    // -------------------------
    // Phase 3 Mint
    // -------------------------

    function mintPhaseThree(
        uint256 quantity
    ) external payable nonReentrant whenNotPaused {
        require(activePhase == PHASE_THREE, "Phase 3 inactive");
        require(quantity > 0 && quantity <= 2, "Invalid quantity");
        require(
            mintedPerPhase[PHASE_THREE][msg.sender] + quantity <= 2,
            "Phase 3 wallet cap"
        );
        require(
            phaseThreeMinted + quantity <= PHASE_THREE_SUPPLY,
            "Phase 3 sold out"
        );
        require(msg.value == phaseThreePrice * quantity, "Wrong ETH");

        mintRevenue += msg.value;
        mintedPerPhase[PHASE_THREE][msg.sender] += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            phaseThreeMinted++;
            _mintWorld(msg.sender, PHASE_THREE);
        }
    }

    // -------------------------
    // Phase 4 Mint
    // -------------------------

    function mintPhaseFour(
        uint256 quantity,
        uint256[] calldata passIds
    ) external payable nonReentrant whenNotPaused {
        require(activePhase == PHASE_FOUR, "Phase 4 inactive");
        require(quantity > 0 && quantity <= 2, "Invalid quantity");
        require(passIds.length == quantity, "Pass count mismatch");
        require(
            mintedPerPhase[PHASE_FOUR][msg.sender] + quantity <= 2,
            "Phase 4 wallet cap"
        );
        require(
            phaseFourMinted + quantity <= PHASE_FOUR_SUPPLY,
            "Phase 4 sold out"
        );
        require(msg.value == phaseFourPrice * quantity, "Wrong ETH");

        mintRevenue += msg.value;

        for (uint256 i = 0; i < passIds.length; i++) {
            require(
                passContract.ownerOf(passIds[i]) == msg.sender,
                "Not pass owner"
            );
            require(
                passContract.canUseForPhase(passIds[i], PHASE_FOUR),
                "Pass not valid"
            );

            for (uint256 j = i + 1; j < passIds.length; j++) {
                require(passIds[i] != passIds[j], "Duplicate pass");
            }

            passContract.markPassUsedForPhase(passIds[i], PHASE_FOUR);
        }

        mintedPerPhase[PHASE_FOUR][msg.sender] += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            phaseFourMinted++;
            _mintWorld(msg.sender, PHASE_FOUR);
        }
    }

    // -------------------------
    // Internal Mint
    // -------------------------

    function _mintWorld(address to, uint8 phase) internal {
        require(totalMinted < MAX_SUPPLY, "Max supply reached");

        totalMinted++;
        uint256 tokenId = totalMinted;

        tokenPhase[tokenId] = phase;
        tokenSeed[tokenId] = uint64(
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao,
                        blockhash(block.number - 1),
                        to,
                        tokenId,
                        phase
                    )
                )
            )
        );

        _safeMint(to, tokenId);

        activeShareSupply++;
        feeDebt[tokenId] = accFeePerShare;

        emit WorldMinted(to, tokenId, phase);
    }

    // -------------------------
    // Marketplace
    // -------------------------

    function depositMarketplaceFees() external payable {
        require(msg.value > 0, "No ETH sent");
        require(activeShareSupply > 0, "No active shares");

        totalFeeShareReceived += msg.value;
        accFeePerShare += (msg.value * FEE_PRECISION) / activeShareSupply;
    }

    function claimMarketplaceFees(
        uint256[] calldata tokenIds
    ) external nonReentrant {
        uint256 totalClaim;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            require(ownerOf(tokenId) == msg.sender, "Not token owner");

            uint256 claimable = accFeePerShare - feeDebt[tokenId];

            if (claimable > 0) {
                feeDebt[tokenId] = accFeePerShare;
                totalClaim += claimable / FEE_PRECISION;
            }
        }

        require(totalClaim > 0, "Nothing to claim");

        (bool ok, ) = payable(msg.sender).call{value: totalClaim}("");
        require(ok, "Claim failed");
    }

    // -------------------------
    // Burn for Reward
    // -------------------------

    function burnForReward(
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!burnedForReward[tokenId], "Already burned");

        uint8 tier = rewardTier[tokenId];
        require(tier != REWARD_NONE, "No reward");

        uint256 gross = _rewardAmountForBurn(tier);
        require(gross > 0, "Reward not set");
        require(rewardPoolFunded >= gross, "Reward pool low");

        uint256 fee = (gross * BURN_FEE_BPS) / BPS_DENOMINATOR;
        uint256 net = gross - fee;

        burnedForReward[tokenId] = true;
        rewardPoolFunded -= gross;
        burnFeesCollected += fee;

        if (activeShareSupply > 0) {
            activeShareSupply--;
        }

        feeDebt[tokenId] = 0;

        if (tier == REWARD_RARE) {
            require(rareRemaining > 0, "Rare remaining error");
            rareRemaining--;
        }

        if (tier == REWARD_SUPER_RARE) {
            require(superRareRemaining > 0, "Super rare remaining error");
            superRareRemaining--;
        }

        _burn(tokenId);

        (bool ok, ) = payable(msg.sender).call{value: net}("");
        require(ok, "Payout failed");

        emit NFTBurnedForReward(tokenId, msg.sender, tier, gross, fee, net);
    }

    function withdrawBurnFees(address payable to) external onlyOwner {
        require(to != address(0), "Invalid receiver");

        uint256 amount = burnFeesCollected;
        burnFeesCollected = 0;

        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
    }

    // -------------------------
    // Views
    // -------------------------

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // renderer uses 0,1,2,3 phase IDs
        uint8 rendererPhase = tokenPhase[tokenId] - 1;

        return renderer.tokenURIForPhase(tokenId, rendererPhase);
    }

    function phaseOneMinterCount() external view returns (uint256) {
        return phaseOneMinters.length;
    }

    function priceForPhase(uint8 phase) external view returns (uint256) {
        if (phase == PHASE_ONE) return phaseOnePrice;
        if (phase == PHASE_TWO) return phaseTwoPrice;
        if (phase == PHASE_THREE) return phaseThreePrice;
        if (phase == PHASE_FOUR) return phaseFourPrice;
        return 0;
    }

    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
