// SPDX-License-Identifier: MIT
// ════════════════════════════════════════════════════════════════
//   Pawn-5D · PAWN
//   Website  : https://pawn5d.com
//   App      : https://app.pawn5d.com
//   Twitter  : https://x.com/Pawn_ERC5D
// ════════════════════════════════════════════════════════════════
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TierMath} from "./lib/TierMath.sol";
import {IPawnTreasury} from "./interfaces/IPawnTreasury.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

contract PawnTreasury is IPawnTreasury, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant CLAIM_WINDOW = 86400;
    uint256 public constant MIN_EPOCH_DURATION = 3600;
    uint256 public constant MAX_EPOCH_DURATION = 2592000;
    uint256 public constant PRECISION = 1e18;

    address public pawnToken;
    address public immutable unclaimedReserveWallet;
    address public uniswapV2Pair;

    bool public treasuryActive;
    bool public autoDistribute;
    uint256 public epochAnchor;
    uint256 public epochDuration = 14400;
    uint256 public lastDistributedEpoch;
    uint256 public pendingETH;

    uint256 public phalanxReserve;
    uint256 public phalanxEmissionPerEpoch;

    uint256 public unsweptETH;
    uint256 public unsweptToken;

    mapping(uint8 => uint256) public tierNFTCount;
    mapping(address => mapping(uint8 => uint256)) public holderTierCount;
    mapping(uint8 => uint256) public accETHPerNFT;
    mapping(uint8 => uint256) public accTokenPerNFT;
    mapping(address => mapping(uint8 => uint256)) public rewardDebtETH;
    mapping(address => mapping(uint8 => uint256)) public rewardDebtToken;
    mapping(address => uint256) public pendingClaimETH;
    mapping(address => uint256) public pendingClaimToken;

    mapping(uint256 => mapping(uint8 => uint256)) public epochAccETH;
    mapping(uint256 => mapping(uint8 => uint256)) public epochAccToken;
    mapping(uint256 => uint256) public epochDistributedAt;
    mapping(address => uint256) public nextClaimEpoch;

    bool private _distributionStarted;

    event TreasuryInitialized(uint256 epochAnchor);
    event EpochDistributed(
        uint256 indexed epochIndex,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 distributedAt
    );
    event Claimed(
        address indexed holder,
        uint256 indexed epochFrom,
        uint256 indexed epochTo,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event EmissionChanged(uint256 newRatePerEpoch);
    event EpochDurationChanged(uint256 newDuration, uint256 newAnchor);
    event AutoDistributeChanged(bool enabled);
    event UnclaimedSwept(uint256 ethAmount, uint256 tokenAmount);
    event PhalanxFed(uint256 amount);
    event PawnTokenSet(address indexed token);
    event PairSet(address indexed pair);

    modifier onlyPawnToken() {
        require(pawnToken != address(0), "token not wired");
        require(msg.sender == pawnToken, "only pawnToken");
        _;
    }

    modifier onlyActive() {
        require(treasuryActive, "treasury not active");
        _;
    }

    constructor(address unclaimedReserveWallet_) Ownable(msg.sender) {
        require(unclaimedReserveWallet_ != address(0), "zero reserve wallet");
        unclaimedReserveWallet = unclaimedReserveWallet_;
    }

    function setPawnToken(address token_) external onlyOwner {
        require(pawnToken == address(0), "already set");
        require(token_ != address(0), "zero address");
        pawnToken = token_;
        emit PawnTokenSet(token_);
    }

    function setPair(address pair_) external onlyOwner {
        uniswapV2Pair = pair_;
        emit PairSet(pair_);
    }

    function initializeTreasury() external onlyOwner {
        require(!treasuryActive, "already active");
        treasuryActive = true;
        epochAnchor = block.timestamp;
        lastDistributedEpoch = 0;
        emit TreasuryInitialized(block.timestamp);
    }

    function receiveETH() external payable onlyPawnToken onlyActive {
        pendingETH += msg.value;
        if (autoDistribute) {
            uint256 epoch = currentEpoch();
            uint256 nextToDistribute = _distributionStarted ? lastDistributedEpoch + 1 : 0;
            if (epoch > nextToDistribute) {
                _distributeUpTo(epoch - 1);
            }
        }
    }

    function onNFTMint(address holder, uint8 tier) external onlyPawnToken {
        require(tier >= 1 && tier <= 4, "bad tier");
        if (holderTierCount[holder][tier] == 0) {
            rewardDebtETH[holder][tier] = accETHPerNFT[tier];
            rewardDebtToken[holder][tier] = accTokenPerNFT[tier];
        }
        holderTierCount[holder][tier]++;
        tierNFTCount[tier]++;
    }

    function onNFTBurn(address holder, uint8 tier, bool isSell) external onlyPawnToken {
        require(tier >= 1 && tier <= 4, "bad tier");
        uint256 count = holderTierCount[holder][tier];
        require(count > 0, "no NFTs in tier");

        uint256 accETH = accETHPerNFT[tier];
        uint256 accToken = accTokenPerNFT[tier];

        uint256 earnedETH = (count * (accETH - rewardDebtETH[holder][tier])) / PRECISION;
        uint256 earnedToken = (count * (accToken - rewardDebtToken[holder][tier])) / PRECISION;

        if (isSell) {
            unsweptETH += earnedETH;
            unsweptToken += earnedToken;
        } else {
            pendingClaimETH[holder] += earnedETH;
            pendingClaimToken[holder] += earnedToken;
        }

        holderTierCount[holder][tier] = 0;
        tierNFTCount[tier] -= count;

        rewardDebtETH[holder][tier] = accETH;
        rewardDebtToken[holder][tier] = accToken;
    }

    function settleHolder(address holder) external onlyPawnToken {
        for (uint8 t = 1; t <= 4; t++) {
            uint256 count = holderTierCount[holder][t];
            if (count == 0) continue;
            uint256 earnedETH =
                (count * (accETHPerNFT[t] - rewardDebtETH[holder][t])) / PRECISION;
            uint256 earnedToken =
                (count * (accTokenPerNFT[t] - rewardDebtToken[holder][t])) / PRECISION;
            pendingClaimETH[holder] += earnedETH;
            pendingClaimToken[holder] += earnedToken;
            rewardDebtETH[holder][t] = accETHPerNFT[t];
            rewardDebtToken[holder][t] = accTokenPerNFT[t];
        }
    }

    function distributeEpoch() external onlyOwner onlyActive {
        uint256 epoch = currentEpoch();
        uint256 nextToDistribute = _distributionStarted ? lastDistributedEpoch + 1 : 0;
        require(epoch > nextToDistribute, "nothing to distribute");
        _distributeUpTo(epoch - 1);
    }

    function _distributeUpTo(uint256 targetEpoch) internal {
        uint256 from = _distributionStarted ? lastDistributedEpoch + 1 : 0;
        for (uint256 e = from; e <= targetEpoch; e++) {
            _distributeOneEpoch(e);
        }
    }

    function _distributeOneEpoch(uint256 epochIndex) internal {
        uint256 ethForEpoch = pendingETH;
        pendingETH = 0;

        uint256 epochRelease = phalanxEmissionPerEpoch;
        if (epochRelease > phalanxReserve) {
            epochRelease = phalanxReserve;
        }
        phalanxReserve -= epochRelease;

        uint256 totalWeight;
        uint256[4] memory rates;
        for (uint8 t = 1; t <= 4; t++) {
            rates[t - 1] = TierMath.tierRate(t, epochIndex);
            totalWeight += rates[t - 1] * tierNFTCount[t];
        }

        if (totalWeight > 0) {
            for (uint8 t = 1; t <= 4; t++) {
                if (tierNFTCount[t] == 0 || rates[t - 1] == 0) continue;

                uint256 tierShareETH = (ethForEpoch * rates[t - 1]) / totalWeight;
                uint256 tierShareToken = (epochRelease * rates[t - 1]) / totalWeight;

                accETHPerNFT[t] += (tierShareETH * PRECISION) / tierNFTCount[t];
                accTokenPerNFT[t] += (tierShareToken * PRECISION) / tierNFTCount[t];
            }
        }

        for (uint8 t = 1; t <= 4; t++) {
            epochAccETH[epochIndex][t] = accETHPerNFT[t];
            epochAccToken[epochIndex][t] = accTokenPerNFT[t];
        }
        epochDistributedAt[epochIndex] = block.timestamp;
        lastDistributedEpoch = epochIndex;
        _distributionStarted = true;

        emit EpochDistributed(epochIndex, ethForEpoch, epochRelease, block.timestamp);
    }

    function claim() external nonReentrant onlyActive {
        address holder = msg.sender;

        uint256 claimableFrom = nextClaimEpoch[holder];
        uint256 claimableTo = lastDistributedEpoch;

        while (
            claimableFrom <= claimableTo
                && epochDistributedAt[claimableFrom] != 0
                && epochDistributedAt[claimableFrom] + CLAIM_WINDOW < block.timestamp
        ) {
            claimableFrom++;
        }

        uint256 totalETH = pendingClaimETH[holder];
        uint256 totalToken = pendingClaimToken[holder];

        bool hasEpochRewards = false;

        if (
            _distributionStarted && claimableFrom <= claimableTo
                && epochDistributedAt[claimableFrom] != 0
                && epochDistributedAt[claimableFrom] + CLAIM_WINDOW >= block.timestamp
        ) {
            for (uint8 t = 1; t <= 4; t++) {
                uint256 count = holderTierCount[holder][t];
                if (count == 0) continue;

                uint256 baseAccETH = claimableFrom > 0 ? epochAccETH[claimableFrom - 1][t] : 0;
                uint256 baseAccToken = claimableFrom > 0 ? epochAccToken[claimableFrom - 1][t] : 0;

                uint256 topAccETH = epochAccETH[claimableTo][t];
                uint256 topAccToken = epochAccToken[claimableTo][t];

                if (topAccETH >= baseAccETH) {
                    totalETH += (count * (topAccETH - baseAccETH)) / PRECISION;
                }
                if (topAccToken >= baseAccToken) {
                    totalToken += (count * (topAccToken - baseAccToken)) / PRECISION;
                }

                rewardDebtETH[holder][t] = topAccETH;
                rewardDebtToken[holder][t] = topAccToken;
            }
            hasEpochRewards = true;
        }

        require(totalETH > 0 || totalToken > 0, "nothing to claim");

        pendingClaimETH[holder] = 0;
        pendingClaimToken[holder] = 0;

        if (hasEpochRewards) {
            nextClaimEpoch[holder] = claimableTo + 1;
        }

        if (totalETH > 0) {
            (bool ok,) = payable(holder).call{value: totalETH}("");
            require(ok, "ETH transfer failed");
        }
        if (totalToken > 0) {
            IERC20(pawnToken).safeTransfer(holder, totalToken);
        }

        emit Claimed(holder, claimableFrom, claimableTo, totalETH, totalToken);
    }

    function setPhalanxEmission(uint256 ratePerEpoch) external onlyOwner {
        phalanxEmissionPerEpoch = ratePerEpoch;
        emit EmissionChanged(ratePerEpoch);
    }

    function feedPhalanx(uint256 amount) external onlyOwner {
        require(pawnToken != address(0), "token not wired");
        require(amount > 0, "zero amount");
        IERC20(pawnToken).safeTransferFrom(msg.sender, address(this), amount);
        phalanxReserve += amount;
        emit PhalanxFed(amount);
    }

    function setAutoDistribute(bool enabled) external onlyOwner {
        autoDistribute = enabled;
        emit AutoDistributeChanged(enabled);
    }

    function sweepUnclaimed() external onlyOwner nonReentrant {
        uint256 ethToSweep = unsweptETH;
        uint256 tokenToSweep = unsweptToken;

        require(ethToSweep > 0 || tokenToSweep > 0, "nothing to sweep");

        unsweptETH = 0;
        unsweptToken = 0;

        if (ethToSweep > 0) {
            (bool ok,) = payable(unclaimedReserveWallet).call{value: ethToSweep}("");
            require(ok, "ETH sweep failed");
        }
        if (tokenToSweep > 0) {
            IERC20(pawnToken).safeTransfer(unclaimedReserveWallet, tokenToSweep);
        }

        emit UnclaimedSwept(ethToSweep, tokenToSweep);
    }

    function setEpochDuration(uint256 seconds_) external onlyOwner onlyActive {
        require(seconds_ >= MIN_EPOCH_DURATION && seconds_ <= MAX_EPOCH_DURATION, "out of bounds");
        uint256 closedEpochs = (block.timestamp - epochAnchor) / epochDuration;
        uint256 newAnchor = epochAnchor + (closedEpochs * epochDuration);
        epochAnchor = newAnchor;
        epochDuration = seconds_;
        emit EpochDurationChanged(seconds_, newAnchor);
    }

    function migrate() external onlyOwner nonReentrant {
        uint256 ethBal = address(this).balance;
        uint256 tokenBal = pawnToken != address(0) ? IERC20(pawnToken).balanceOf(address(this)) : 0;

        if (ethBal > 0) {
            (bool ok,) = payable(owner()).call{value: ethBal}("");
            require(ok, "ETH migrate failed");
        }
        if (tokenBal > 0) {
            IERC20(pawnToken).safeTransfer(owner(), tokenBal);
        }
    }

    function currentEpoch() public view returns (uint256) {
        if (!treasuryActive) return 0;
        return (block.timestamp - epochAnchor) / epochDuration;
    }

    function pendingRewards(address holder)
        external
        view
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        ethAmount = pendingClaimETH[holder];
        tokenAmount = pendingClaimToken[holder];

        if (!_distributionStarted) return (ethAmount, tokenAmount);

        uint256 claimableFrom = nextClaimEpoch[holder];
        uint256 claimableTo = lastDistributedEpoch;

        while (
            claimableFrom <= claimableTo
                && epochDistributedAt[claimableFrom] != 0
                && epochDistributedAt[claimableFrom] + CLAIM_WINDOW < block.timestamp
        ) {
            claimableFrom++;
        }

        if (
            claimableFrom > claimableTo || epochDistributedAt[claimableFrom] == 0
                || epochDistributedAt[claimableFrom] + CLAIM_WINDOW < block.timestamp
        ) {
            return (ethAmount, tokenAmount);
        }

        for (uint8 t = 1; t <= 4; t++) {
            uint256 count = holderTierCount[holder][t];
            if (count == 0) continue;
            uint256 baseETH = claimableFrom > 0 ? epochAccETH[claimableFrom - 1][t] : 0;
            uint256 baseToken = claimableFrom > 0 ? epochAccToken[claimableFrom - 1][t] : 0;
            uint256 topETH = epochAccETH[claimableTo][t];
            uint256 topToken = epochAccToken[claimableTo][t];
            if (topETH >= baseETH) ethAmount += (count * (topETH - baseETH)) / PRECISION;
            if (topToken >= baseToken) tokenAmount += (count * (topToken - baseToken)) / PRECISION;
        }
    }

    function phalanxReserveRemaining() external view returns (uint256) {
        return phalanxReserve;
    }

    function getMcapApprox() external view returns (uint256 ethValue) {
        if (uniswapV2Pair == address(0) || pawnToken == address(0)) return 0;
        IUniswapV2Pair pair = IUniswapV2Pair(uniswapV2Pair);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        address t0 = pair.token0();
        uint112 ethReserve;
        uint112 tokenReserve;
        if (t0 == pawnToken) {
            tokenReserve = r0;
            ethReserve = r1;
        } else {
            ethReserve = r0;
            tokenReserve = r1;
        }
        if (tokenReserve == 0) return 0;
        uint256 totalSupply = IERC20(pawnToken).totalSupply();
        ethValue = (totalSupply * uint256(ethReserve)) / uint256(tokenReserve);
    }

    function epochDistributedAtView(uint256 epochIndex) external view returns (uint256) {
        return epochDistributedAt[epochIndex];
    }

    function lastDistributedEpochView() external view returns (uint256) {
        return lastDistributedEpoch;
    }

    function tierHolderCount(uint8 tier) external view returns (uint256) {
        return tierNFTCount[tier];
    }

    function website() external pure returns (string memory) {
        return "https://pawn5d.com";
    }

    function app() external pure returns (string memory) {
        return "https://app.pawn5d.com";
    }

    function twitter() external pure returns (string memory) {
        return "https://x.com/Pawn_ERC5D";
    }

    receive() external payable {}
}
