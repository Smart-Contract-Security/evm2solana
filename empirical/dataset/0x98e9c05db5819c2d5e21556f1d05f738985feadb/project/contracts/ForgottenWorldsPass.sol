// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ForgottenWorldsPass is ERC721, Ownable {
    uint8 public constant PHASE_ONE = 1;
    uint8 public constant PHASE_FOUR = 4;

    uint256 public constant INITIAL_PASS_SUPPLY = 1500;
    uint256 public constant PHASE_ONE_REWARD_SUPPLY = 400;
    uint256 public constant PHASE_TWO_REWARD_SUPPLY = 600;
    uint256 public constant MAX_SUPPLY =
        INITIAL_PASS_SUPPLY + PHASE_ONE_REWARD_SUPPLY + PHASE_TWO_REWARD_SUPPLY;

    enum PassType {
        InitialPhaseOne,
        PhaseOneReward,
        PhaseTwoReward
    }

    uint256 public totalMinted;
    uint256 public initialPassMinted;
    uint256 public phaseOneRewardMinted;
    uint256 public phaseTwoRewardMinted;

    address public mintContract;
    address public marketplace;

    bool public claimActive;

    mapping(address => bool) public hasClaimedInitialPass;
    mapping(uint256 => PassType) public passTypeOf;
    mapping(uint256 => mapping(uint8 => bool)) public passUsedForPhase;
    mapping(uint256 => uint8) public lockedUntilPhase;

    event ClaimActiveUpdated(bool active);
    event MintContractUpdated(address indexed mintContract);
    event MarketplaceUpdated(address indexed marketplace);
    event PassUsedForPhase(uint256 indexed passId, uint8 indexed phaseId);
    event PassUnlocked(uint256 indexed passId);

    modifier onlyMintContract() {
        require(msg.sender == mintContract, "Not mint contract");
        _;
    }

    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "Not marketplace");
        _;
    }

    constructor() ERC721("Forgotten Worlds Pass", "FWPASS") Ownable(msg.sender) {}

    // -------------------------
    // Admin
    // -------------------------

    function setClaimActive(bool active) external onlyOwner {
        claimActive = active;
        emit ClaimActiveUpdated(active);
    }

    function setMintContract(address _mintContract) external onlyOwner {
        require(_mintContract != address(0), "Zero address");
        mintContract = _mintContract;
        emit MintContractUpdated(_mintContract);
    }

    function setMarketplace(address _marketplace) external onlyOwner {
        require(_marketplace != address(0), "Zero address");
        marketplace = _marketplace;
        emit MarketplaceUpdated(_marketplace);
    }

    // -------------------------
    // Initial Free Pass Claim
    // -------------------------

    function claimInitialPass() external {
        require(claimActive, "Claim not active");
        require(!hasClaimedInitialPass[msg.sender], "Already claimed");
        require(initialPassMinted < INITIAL_PASS_SUPPLY, "Initial pass sold out");

        hasClaimedInitialPass[msg.sender] = true;
        initialPassMinted++;

        _mintPass(msg.sender, PassType.InitialPhaseOne);
    }

    // -------------------------
    // Reward Pass Minting
    // -------------------------

    function mintPhaseOneRewardPass(address to) external onlyMintContract {
        require(phaseOneRewardMinted < PHASE_ONE_REWARD_SUPPLY, "P1 rewards finished");

        phaseOneRewardMinted++;
        _mintPass(to, PassType.PhaseOneReward);
    }

    function mintPhaseTwoRewardPass(address to) external onlyMintContract {
        require(phaseTwoRewardMinted < PHASE_TWO_REWARD_SUPPLY, "P2 rewards finished");

        phaseTwoRewardMinted++;
        _mintPass(to, PassType.PhaseTwoReward);
    }

    function mintPhaseTwoRewardPasses(address to) external onlyMintContract {
        require(phaseTwoRewardMinted + 2 <= PHASE_TWO_REWARD_SUPPLY, "P2 rewards finished");

        phaseTwoRewardMinted += 2;
        _mintPass(to, PassType.PhaseTwoReward);
        _mintPass(to, PassType.PhaseTwoReward);
    }

    function _mintPass(address to, PassType passType_) internal {
        require(totalMinted < MAX_SUPPLY, "Max pass supply reached");

        totalMinted++;
        uint256 tokenId = totalMinted;

        passTypeOf[tokenId] = passType_;
        _safeMint(to, tokenId);
    }

    // -------------------------
    // Mint Contract Controls
    // -------------------------

    function markPassUsedForPhase(uint256 passId, uint8 phaseId) external onlyMintContract {
        require(_ownerOf(passId) != address(0), "Invalid pass");
        require(!passUsedForPhase[passId][phaseId], "Pass already used");

        passUsedForPhase[passId][phaseId] = true;
        lockedUntilPhase[passId] = phaseId;

        emit PassUsedForPhase(passId, phaseId);
    }

    function unlockPass(uint256 passId) external onlyMintContract {
        require(_ownerOf(passId) != address(0), "Invalid pass");
        lockedUntilPhase[passId] = 0;

        emit PassUnlocked(passId);
    }

    // -------------------------
    // Marketplace Transfers
    // -------------------------

    function marketplaceTransfer(address from, address to, uint256 passId) external onlyMarketplace {
        require(ownerOf(passId) == from, "Not owner");
        require(isRewardPass(passId), "Initial pass not transferable");

        _safeTransfer(from, to, passId, "");
    }

    // -------------------------
    // View Helpers
    // -------------------------

    function isInitialPass(uint256 passId) public view returns (bool) {
        return passTypeOf[passId] == PassType.InitialPhaseOne;
    }

    function isRewardPass(uint256 passId) public view returns (bool) {
        return
            passTypeOf[passId] == PassType.PhaseOneReward ||
            passTypeOf[passId] == PassType.PhaseTwoReward;
    }

    function isSellable(uint256 passId) external view returns (bool) {
        if (_ownerOf(passId) == address(0)) return false;
        if (!isRewardPass(passId)) return false;
        if (lockedUntilPhase[passId] != 0) return false;
        return true;
    }

    function canUseForPhase(uint256 passId, uint8 phaseId) external view returns (bool) {
        if (_ownerOf(passId) == address(0)) return false;
        if (passUsedForPhase[passId][phaseId]) return false;

        if (phaseId == PHASE_ONE) {
            return passTypeOf[passId] == PassType.InitialPhaseOne;
        }

        if (phaseId == PHASE_FOUR) {
            return isRewardPass(passId);
        }

        return false;
    }

    // -------------------------
    // Transfer Restriction
    // -------------------------

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        bool isMint = from == address(0);
        bool isBurn = to == address(0);

        if (!isMint && !isBurn) {
            require(msg.sender == marketplace, "Pass transfers only through marketplace");
            require(isRewardPass(tokenId), "Initial pass cannot be transferred");
            require(lockedUntilPhase[tokenId] == 0, "Pass locked until phase ends");
        }

        return super._update(to, tokenId, auth);
    }
}
