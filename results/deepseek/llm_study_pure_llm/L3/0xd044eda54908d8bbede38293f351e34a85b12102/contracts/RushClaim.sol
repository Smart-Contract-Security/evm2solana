// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGateCoin} from "./interfaces/IGateCoin.sol";
import {IRushBurn} from "./interfaces/IRushBurn.sol";

contract RushClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error PhaseClosed();
    error PhaseAlreadyOpen();
    error PhaseNotEnded();
    error PhaseTooShort();
    error CannotRescueRush();
    error NothingToClaim();
    error NotEOA();

    uint256 public constant TAU_SECONDS = 36 hours;
    uint256 public constant E4 = 10_000;
    uint256 public constant MIN_CLAIM_DURATION = 96 hours;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant K_NFT_1_E4 = 10_000;
    uint256 public constant K_NFT_2_E4 = 20_000;
    uint256 public constant K_NFT_3_E4 = 35_000;

    IERC20 public immutable rush;
    IGateCoin public immutable gateCoin;
    IRushBurn public immutable burnContract;

    bool public phaseOpen;
    uint64 public phaseStart;
    uint64 public phaseEnd;

    struct ClaimRecord {
        uint128 sCredited;
        uint128 claimed;
        uint64 lastClaimAt;
    }
    mapping(address => ClaimRecord) public records;

    uint256 public totalCredited;
    uint256 public totalClaimed;

    event PhaseOpened(uint64 start, uint64 end);
    event PhaseClosedEvent(uint64 timestamp, uint256 remainder);
    event SpinCredited(address indexed user, uint256 amount, uint256 totalCredited);
    event Claimed(
        address indexed user,
        uint256 amount,
        uint256 cumulativeClaimed,
        uint256 wRemaining,
        uint256 kTotalE4
    );

    constructor(address _rush, address _gateCoin, address _burn) Ownable(msg.sender) {
        rush = IERC20(_rush);
        gateCoin = IGateCoin(_gateCoin);
        burnContract = IRushBurn(_burn);
    }

    function openPhase(uint64 endTimestamp) external onlyOwner {
        if (phaseOpen) revert PhaseAlreadyOpen();
        if (endTimestamp < block.timestamp + MIN_CLAIM_DURATION) revert PhaseTooShort();
        phaseOpen = true;
        phaseStart = uint64(block.timestamp);
        phaseEnd = endTimestamp;
        emit PhaseOpened(phaseStart, endTimestamp);
    }

    function closePhase() external {
        if (!phaseOpen) revert PhaseClosed();
        if (block.timestamp < phaseEnd) revert PhaseNotEnded();
        phaseOpen = false;
        uint256 bal = rush.balanceOf(address(this));
        if (bal > 0) rush.safeTransfer(DEAD, bal);
        emit PhaseClosedEvent(uint64(block.timestamp), bal);
    }

    function claim() external nonReentrant {
        if (msg.sender != tx.origin) revert NotEOA();
        if (!phaseOpen) revert PhaseClosed();
        if (block.timestamp >= phaseEnd) revert PhaseClosed();

        _materializeS(msg.sender);

        uint256 amount = claimable(msg.sender);
        if (amount == 0) revert NothingToClaim();

        ClaimRecord storage rec = records[msg.sender];
        rec.claimed += uint128(amount);
        rec.lastClaimAt = uint64(block.timestamp);
        totalClaimed += amount;

        rush.safeTransfer(msg.sender, amount);

        (uint256 w, uint256 kTotal) = _wAndK(msg.sender);
        uint256 remaining = w > rec.claimed ? w - rec.claimed : 0;
        emit Claimed(msg.sender, amount, rec.claimed, remaining, kTotal);
    }

    function claimable(address user) public view returns (uint256) {
        if (!phaseOpen) return 0;
        if (block.timestamp >= phaseEnd) return 0;

        ClaimRecord memory rec = records[user];
        (uint256 w, ) = _wAndKPreview(user);
        if (w <= rec.claimed) return 0;

        uint256 since = block.timestamp - (rec.lastClaimAt == 0 ? phaseStart : rec.lastClaimAt);
        uint256 byRate = (w * since) / TAU_SECONDS;
        uint256 hardRemaining = w - rec.claimed;
        return byRate < hardRemaining ? byRate : hardRemaining;
    }

    function previewW(address user) external view returns (uint256 w, uint256 kE8) {
        return _wAndKPreview(user);
    }

    function _materializeS(address user) internal {
        ClaimRecord storage rec = records[user];
        if (rec.sCredited != 0) return;
        if (gateCoin.balanceOf(user) == 0) return;
        uint256 s = gateCoin.spinReward(user);
        if (s == 0) return;
        rec.sCredited = uint128(s);
        totalCredited += s;
        emit SpinCredited(user, s, totalCredited);
    }

    function _wAndK(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 s = records[user].sCredited;
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(gateCoin.balanceOf(user));
        uint256 kBrnE4 = burnContract.kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w = (s * kE8) / 1e8;
    }

    function _wAndKPreview(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 nftCount = gateCoin.balanceOf(user);
        if (nftCount == 0) return (0, 0);

        uint256 s = records[user].sCredited;
        if (s == 0) s = gateCoin.spinReward(user);
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(nftCount);
        uint256 kBrnE4 = burnContract.kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w = (s * kE8) / 1e8;
    }

    function _kNftE4(uint256 nftCount) internal pure returns (uint256) {
        if (nftCount >= 3) return K_NFT_3_E4;
        if (nftCount == 2) return K_NFT_2_E4;
        if (nftCount == 1) return K_NFT_1_E4;
        return E4;
    }

    function rescueERC20(address token, uint256 amount) external onlyOwner {
        if (token == address(rush)) revert CannotRescueRush();
        IERC20(token).safeTransfer(owner(), amount);
    }
}