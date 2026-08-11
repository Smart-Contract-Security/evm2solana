// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

interface IGateCoin {
    function balanceOf(address user) external view returns (uint64);
    function spinReward(address user) external view returns (uint64);
}

interface IRushBurn {
    function kBurnScaled(address user) external view returns (uint64);
}

contract RushClaim {
    uint64 public constant TAU_SECONDS = 129600; // 36 hours in seconds
    uint64 public constant E4 = 10000;
    uint64 public constant MIN_CLAIM_DURATION = 345600; // 96 hours in seconds
    address public constant DEAD = address(0);

    uint64 public constant K_NFT_1_E4 = 10000;
    uint64 public constant K_NFT_2_E4 = 20000;
    uint64 public constant K_NFT_3_E4 = 35000;

    address public immutable rush;
    address public immutable gateCoin;
    address public immutable burnContract;

    address public owner;

    bool public phaseOpen;
    uint64 public phaseStart;
    uint64 public phaseEnd;

    struct ClaimRecord {
        uint64 sCredited;
        uint64 claimed;
        uint64 lastClaimAt;
    }
    mapping(address => ClaimRecord) public records;

    uint64 public totalCredited;
    uint64 public totalClaimed;

    bool private _locked;

    event PhaseOpened(uint64 start, uint64 end);
    event PhaseClosedEvent(uint64 timestamp, uint64 remainder);
    event SpinCredited(address indexed user, uint64 amount, uint64 totalCredited);
    event Claimed(
        address indexed user,
        uint64 amount,
        uint64 cumulativeClaimed,
        uint64 wRemaining,
        uint64 kTotalE4
    );

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "Reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address _rush, address _gateCoin, address _burn) {
        owner = tx.accounts.dataAccount.key;
        rush = _rush;
        gateCoin = _gateCoin;
        burnContract = _burn;
    }

    function openPhase(uint64 endTimestamp) external onlyOwner {
        require(!phaseOpen, "PhaseAlreadyOpen");
        require(endTimestamp >= uint64(block.timestamp) + MIN_CLAIM_DURATION, "PhaseTooShort");
        phaseOpen = true;
        phaseStart = uint64(block.timestamp);
        phaseEnd = endTimestamp;
        emit PhaseOpened(phaseStart, endTimestamp);
    }

    function closePhase() external {
        require(phaseOpen, "PhaseClosed");
        require(block.timestamp >= phaseEnd, "PhaseNotEnded");
        phaseOpen = false;
        uint64 bal = uint64(rush.balance);
        if (bal > 0) {
            AccountMeta[1] meta = [
                AccountMeta({pubkey: rush, is_signer: false, is_writable: true})
            ];
            rush.transfer(DEAD, bal, meta);
        }
        emit PhaseClosedEvent(uint64(block.timestamp), bal);
    }

    function claim() external nonReentrant {
        require(phaseOpen, "PhaseClosed");
        require(block.timestamp < phaseEnd, "PhaseClosed");

        address sender = tx.accounts.dataAccount.key;
        _materializeS(sender);

        uint64 amount = claimable(sender);
        require(amount > 0, "NothingToClaim");

        ClaimRecord storage rec = records[sender];
        rec.claimed += amount;
        rec.lastClaimAt = uint64(block.timestamp);
        totalClaimed += amount;

        AccountMeta[1] meta = [
            AccountMeta({pubkey: rush, is_signer: false, is_writable: true})
        ];
        rush.transfer(sender, amount, meta);

        (uint64 w, uint64 kTotal) = _wAndK(sender);
        uint64 remaining = w > rec.claimed ? w - rec.claimed : 0;
        emit Claimed(sender, amount, rec.claimed, remaining, kTotal);
    }

    function claimable(address user) public view returns (uint64) {
        if (!phaseOpen) return 0;
        if (block.timestamp >= phaseEnd) return 0;

        ClaimRecord memory rec = records[user];
        (uint64 w, ) = _wAndKPreview(user);
        if (w <= rec.claimed) return 0;

        uint64 since = uint64(block.timestamp) - (rec.lastClaimAt == 0 ? phaseStart : rec.lastClaimAt);
        uint64 byRate = (w * since) / TAU_SECONDS;
        uint64 hardRemaining = w - rec.claimed;
        return byRate < hardRemaining ? byRate : hardRemaining;
    }

    function previewW(address user) external view returns (uint64 w, uint64 kE8) {
        return _wAndKPreview(user);
    }

    function _materializeS(address user) internal {
        ClaimRecord storage rec = records[user];
        if (rec.sCredited != 0) return;
        if (IGateCoin(gateCoin).balanceOf(user) == 0) return;
        uint64 s = IGateCoin(gateCoin).spinReward(user);
        if (s == 0) return;
        rec.sCredited = s;
        totalCredited += s;
        emit SpinCredited(user, s, totalCredited);
    }

    function _wAndK(address user) internal view returns (uint64 w, uint64 kE8) {
        uint64 s = records[user].sCredited;
        if (s == 0) return (0, 0);

        uint64 kNftE4 = _kNftE4(IGateCoin(gateCoin).balanceOf(user));
        uint64 kBrnE4 = IRushBurn(burnContract).kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w = (s * kE8) / 100000000;
    }

    function _wAndKPreview(address user) internal view returns (uint64 w, uint64 kE8) {
        uint64 nftCount = IGateCoin(gateCoin).balanceOf(user);
        if (nftCount == 0) return (0, 0);

        uint64 s = records[user].sCredited;
        if (s == 0) s = IGateCoin(gateCoin).spinReward(user);
        if (s == 0) return (0, 0);

        uint64 kNftE4 = _kNftE4(nftCount);
        uint64 kBrnE4 = IRushBurn(burnContract).kBurnScaled(user);

        kE8 = kNftE4 * kBrnE4;
        w = (s * kE8) / 100000000;
    }

    function _kNftE4(uint64 nftCount) internal pure returns (uint64) {
        if (nftCount >= 3) return K_NFT_3_E4;
        if (nftCount == 2) return K_NFT_2_E4;
        if (nftCount == 1) return K_NFT_1_E4;
        return E4;
    }

    function rescueERC20(address token, uint64 amount) external onlyOwner {
        require(token != rush, "CannotRescueRush");
        AccountMeta[1] meta = [
            AccountMeta({pubkey: token, is_signer: false, is_writable: true})
        ];
        token.transfer(owner, amount, meta);
    }
}