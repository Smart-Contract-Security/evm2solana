// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGateCoin {
    function balanceOf(address account) external view returns (uint256);
    function spinReward(address account) external view returns (uint256);
}

interface IRushBurn {
    function kBurnScaled(address account) external view returns (uint256);
}

contract RushClaim {
    using SafeERC20 for IERC20;

    uint256 public constant TAU_SECONDS = 36 hours;
    uint256 public constant E4 = 10_000;
    uint256 public constant MIN_CLAIM_DURATION = 96 hours;
    address public constant DEAD = address(0);

    uint256 public constant K_NFT_1_E4 = 10_000;
    uint256 public constant K_NFT_2_E4 = 20_000;
    uint256 public constant K_NFT_3_E4 = 35_000;

    address public immutable rush;
    address public immutable gateCoin;
    address public immutable burnContract;

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

    address private _owner;

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

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    bool private _locked;

    constructor(address _rush, address _gateCoin, address _burn) {
        _owner = tx.accounts[0].key;
        rush = _rush;
        gateCoin = _gateCoin;
        burnContract = _burn;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function openPhase(uint64 endTimestamp) external onlyOwner {
        require(!phaseOpen, "PhaseAlreadyOpen");
        require(endTimestamp >= block.timestamp + MIN_CLAIM_DURATION, "PhaseTooShort");
        phaseOpen = true;
        phaseStart = uint64(block.timestamp);
        phaseEnd = endTimestamp;
        emit PhaseOpened(phaseStart, endTimestamp);
    }

    function closePhase() external {
        require(phaseOpen, "PhaseClosed");
        require(block.timestamp >= phaseEnd, "PhaseNotEnded");
        phaseOpen = false;
        uint256 bal = IERC20(rush).balanceOf(address(this));
        if (bal > 0) IERC20(rush).safeTransfer(DEAD, bal);
        emit PhaseClosedEvent(uint64(block.timestamp), bal);
    }

    function claim() external nonReentrant {
        require(phaseOpen, "PhaseClosed");
        require(block.timestamp < phaseEnd, "PhaseClosed");

        address sender = tx.accounts[0].key;
        _materializeS(sender);

        uint256 amount = claimable(sender);
        require(amount > 0, "NothingToClaim");

        ClaimRecord storage rec = records[sender];
        rec.claimed += uint128(amount);
        rec.lastClaimAt = uint64(block.timestamp);
        totalClaimed += amount;

        IERC20(rush).safeTransfer(sender, amount);

        (uint256 w, uint256 kTotal) = _wAndK(sender);
        uint256 remaining = w > rec.claimed ? w - rec.claimed : 0;
        emit Claimed(sender, amount, rec.claimed, remaining, kTotal);
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
        if (IGateCoin(gateCoin).balanceOf(user) == 0) return;
        uint256 s = IGateCoin(gateCoin).spinReward(user);
        if (s == 0) return;
        rec.sCredited = uint128(s);
        totalCredited += s;
        emit SpinCredited(user, s, totalCredited);
    }

    function _wAndK(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 s = records[user].sCredited;
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(IGateCoin(gateCoin).balanceOf(user));
        uint256 kBrnE4 = IRushBurn(burnContract).kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w = (s * kE8) / 1e8;
    }

    function _wAndKPreview(address user) internal view returns (uint256 w, uint256 kE8) {
        uint256 nftCount = IGateCoin(gateCoin).balanceOf(user);
        if (nftCount == 0) return (0, 0);

        uint256 s = records[user].sCredited;
        if (s == 0) s = IGateCoin(gateCoin).spinReward(user);
        if (s == 0) return (0, 0);

        uint256 kNftE4 = _kNftE4(nftCount);
        uint256 kBrnE4 = IRushBurn(burnContract).kBurnScaled(user);

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
        require(token != rush, "CannotRescueRush");
        IERC20(token).safeTransfer(owner(), amount);
    }
}