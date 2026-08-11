// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IConstellationLightNft {
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenSlot(uint256 tokenId) external view returns (uint256);
}

interface IWETH is IERC20 {
    function withdraw(uint256 amount) external;
}

/// @notice Receives creator earnings, reserves half for the owner, and lets current NFT owners claim the holder half.
/// @dev NFTs never leave the owner wallet. Unclaimed rewards follow the NFT to its current owner.
contract ConstellationLightVault is Ownable, ReentrancyGuard {
    uint256 private constant ACC_SCALE = 1e18;
    uint256 private constant BPS = 10_000;
    uint256 private constant RARE_THRESHOLD = 3_350_074_491;
    uint256 private constant EPIC_THRESHOLD = 3_951_369_913;
    uint256 private constant MYTHIC_THRESHOLD = 4_230_549_177;

    uint256 public constant HARD_MAX_SUPPLY = 2_222;
    uint256 public constant ORIGIN_SLOT_COUNT = 88;
    uint256 public constant MAX_ATTUNE_PER_TX = 40;
    uint256 public constant MAX_CLAIM_PER_TX = 60;
    uint256 public constant MIN_REGISTERED_WALLETS_FOR_CLAIM = 10;
    uint256 public constant FIRST_CLAIM_DELAY = 10 minutes;
    uint256 public constant COMMON_LIGHT = 1;
    uint256 public constant RARE_LIGHT = 3;
    uint256 public constant EPIC_LIGHT = 8;
    uint256 public constant MYTHIC_LIGHT = 20;
    uint256 public constant ORIGIN_LIGHT = 25;
    uint256 public constant OWNER_SHARE_BPS = 5_000;

    IConstellationLightNft public immutable nft;
    IWETH public immutable weth;
    address public immutable ownerPayout;

    uint256 public totalLight;
    uint256 public totalAttuned;
    uint256 public accEthPerLight;
    uint256 public accWethPerLight;
    uint256 public pendingHolderEth;
    uint256 public pendingHolderWeth;
    uint256 public undistributedEth;
    uint256 public undistributedWeth;
    uint256 public ownerEthClaimable;
    uint256 public ownerWethClaimable;
    uint256 public accountedWethBalance;
    uint256 public registeredWalletCount;
    uint64 public claimOpenAt;

    mapping(uint256 tokenId => uint256 light) public tokenLight;
    mapping(uint256 tokenId => uint256 debt) public rewardDebt;
    mapping(uint256 tokenId => uint256 debt) public wethRewardDebt;
    mapping(address wallet => uint256 count) public registeredTokenCount;

    event FeesReceived(
        address indexed sender,
        address indexed asset,
        uint256 amount,
        uint256 ownerAmount,
        uint256 holderAmount
    );
    event LightAttuned(address indexed owner, uint256 indexed tokenId, uint256 indexed slot, uint256 light);
    event LightClaimScheduled(uint64 opensAt);
    event LightClaimed(address indexed owner, uint256 ethAmount, uint256 wethAmount, uint256 quantity);
    event OwnerFeesClaimed(address indexed payout, uint256 ethAmount, uint256 wethAmount);

    constructor(address nftAddress, address initialOwner, address payoutAddress, address wethAddress) {
        require(nftAddress != address(0), "nft required");
        require(initialOwner != address(0), "owner required");
        require(payoutAddress != address(0), "payout required");
        require(wethAddress != address(0), "weth required");
        nft = IConstellationLightNft(nftAddress);
        weth = IWETH(wethAddress);
        ownerPayout = payoutAddress;
        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }
    }

    receive() external payable {
        if (msg.sender == address(weth)) return;
        _receiveEthFees(msg.value);
    }

    function depositFees() external payable nonReentrant {
        _receiveEthFees(msg.value);
    }

    function syncWeth() external nonReentrant {
        _syncWethUnsafe();
    }

    function claimOwnerFees() external nonReentrant {
        _syncWethUnsafe();

        uint256 ethAmount = ownerEthClaimable;
        uint256 wethAmount = ownerWethClaimable;
        require(ethAmount > 0 || wethAmount > 0, "nothing to claim");

        ownerEthClaimable = 0;
        ownerWethClaimable = 0;

        if (ethAmount > 0) {
            (bool ok,) = ownerPayout.call{value: ethAmount}("");
            require(ok, "eth payout failed");
        }
        if (wethAmount > 0) {
            accountedWethBalance -= wethAmount;
            require(weth.transfer(ownerPayout, wethAmount), "weth payout failed");
        }

        emit OwnerFeesClaimed(ownerPayout, ethAmount, wethAmount);
    }

    function claimOwnerFeesAsEth() external nonReentrant {
        _syncWethUnsafe();

        uint256 ethAmount = ownerEthClaimable;
        uint256 wethAmount = ownerWethClaimable;
        require(ethAmount > 0 || wethAmount > 0, "nothing to claim");

        ownerEthClaimable = 0;
        ownerWethClaimable = 0;

        uint256 totalEth = ethAmount;
        if (wethAmount > 0) {
            accountedWethBalance -= wethAmount;
            weth.withdraw(wethAmount);
            totalEth += wethAmount;
        }

        (bool ok,) = ownerPayout.call{value: totalEth}("");
        require(ok, "eth payout failed");

        emit OwnerFeesClaimed(ownerPayout, totalEth, 0);
    }

    function attune(uint256[] calldata tokenIds) external nonReentrant {
        uint256 length = tokenIds.length;
        require(length > 0 && length <= MAX_ATTUNE_PER_TX, "bad quantity");

        _syncWethUnsafe();

        bool newRegistrant = registeredTokenCount[msg.sender] == 0;
        uint256 registeredByWallet = registeredTokenCount[msg.sender];

        for (uint256 index = 0; index < length;) {
            uint256 tokenId = tokenIds[index];
            require(tokenLight[tokenId] == 0, "already attuned");
            require(nft.ownerOf(tokenId) == msg.sender, "not owner");

            uint256 slot = nft.tokenSlot(tokenId);
            uint256 light = lightForSlot(slot);
            require(light > 0, "bad light");

            tokenLight[tokenId] = light;
            rewardDebt[tokenId] = (light * accEthPerLight) / ACC_SCALE;
            wethRewardDebt[tokenId] = (light * accWethPerLight) / ACC_SCALE;
            registeredByWallet += 1;
            totalLight += light;
            totalAttuned += 1;

            emit LightAttuned(msg.sender, tokenId, slot, light);

            unchecked {
                ++index;
            }
        }

        registeredTokenCount[msg.sender] = registeredByWallet;
        if (newRegistrant) {
            registeredWalletCount += 1;
        }

        if (claimOpenAt == 0 && registeredWalletCount >= MIN_REGISTERED_WALLETS_FOR_CLAIM) {
            claimOpenAt = uint64(block.timestamp + FIRST_CLAIM_DELAY);
            emit LightClaimScheduled(claimOpenAt);
        }
    }

    function claim(uint256[] calldata tokenIds) external nonReentrant {
        (uint256 ethTotal, uint256 wethTotal, uint256 length) = _markClaimed(tokenIds, msg.sender);
        require(ethTotal > 0 || wethTotal > 0, "nothing to claim");
        if (ethTotal > 0) {
            (bool ok,) = msg.sender.call{value: ethTotal}("");
            require(ok, "eth claim failed");
        }
        if (wethTotal > 0) {
            accountedWethBalance -= wethTotal;
            require(weth.transfer(msg.sender, wethTotal), "weth claim failed");
        }

        emit LightClaimed(msg.sender, ethTotal, wethTotal, length);
    }

    function claimAsEth(uint256[] calldata tokenIds) external nonReentrant {
        (uint256 ethTotal, uint256 wethTotal, uint256 length) = _markClaimed(tokenIds, msg.sender);
        require(ethTotal > 0 || wethTotal > 0, "nothing to claim");

        uint256 totalEth = ethTotal;
        if (wethTotal > 0) {
            accountedWethBalance -= wethTotal;
            weth.withdraw(wethTotal);
            totalEth += wethTotal;
        }

        (bool ok,) = msg.sender.call{value: totalEth}("");
        require(ok, "eth claim failed");

        emit LightClaimed(msg.sender, totalEth, 0, length);
    }

    function _markClaimed(
        uint256[] calldata tokenIds,
        address claimant
    ) internal returns (uint256 ethTotal, uint256 wethTotal, uint256 length) {
        length = tokenIds.length;
        require(length > 0 && length <= MAX_CLAIM_PER_TX, "bad quantity");
        require(registeredWalletCount >= MIN_REGISTERED_WALLETS_FOR_CLAIM, "not enough wallets");
        require(claimOpenAt != 0 && block.timestamp >= claimOpenAt, "claim delay");
        _syncWethUnsafe();
        _checkpointPending();

        for (uint256 index = 0; index < length;) {
            uint256 tokenId = tokenIds[index];
            uint256 light = tokenLight[tokenId];
            require(light != 0, "not attuned");
            require(nft.ownerOf(tokenId) == claimant, "not owner");

            uint256 ethEarned = (light * accEthPerLight) / ACC_SCALE;
            uint256 ethPending = ethEarned - rewardDebt[tokenId];
            rewardDebt[tokenId] = ethEarned;
            ethTotal += ethPending;

            uint256 wethEarned = (light * accWethPerLight) / ACC_SCALE;
            uint256 wethPending = wethEarned - wethRewardDebt[tokenId];
            wethRewardDebt[tokenId] = wethEarned;
            wethTotal += wethPending;

            unchecked {
                ++index;
            }
        }
    }

    function attuned(uint256 tokenId) external view returns (bool) {
        return tokenLight[tokenId] != 0;
    }

    function attunedSlot(uint256 tokenId) external view returns (uint256) {
        require(tokenLight[tokenId] != 0, "not attuned");
        return nft.tokenSlot(tokenId);
    }

    function claimable(uint256 tokenId) public view returns (uint256) {
        uint256 light = tokenLight[tokenId];
        if (light == 0) return 0;
        uint256 earned = (light * _pendingAccEthPerLight()) / ACC_SCALE;
        return earned - rewardDebt[tokenId];
    }

    function claimableWeth(uint256 tokenId) public view returns (uint256) {
        uint256 light = tokenLight[tokenId];
        if (light == 0) return 0;
        uint256 earned = (light * _syncedAccWethPerLight()) / ACC_SCALE;
        return earned - wethRewardDebt[tokenId];
    }

    function claimableBatch(uint256[] calldata tokenIds) external view returns (uint256 total) {
        for (uint256 index = 0; index < tokenIds.length;) {
            total += claimable(tokenIds[index]);
            unchecked {
                ++index;
            }
        }
    }

    function claimableWethBatch(uint256[] calldata tokenIds) external view returns (uint256 total) {
        for (uint256 index = 0; index < tokenIds.length;) {
            total += claimableWeth(tokenIds[index]);
            unchecked {
                ++index;
            }
        }
    }

    function lightForToken(uint256 tokenId) external view returns (uint256) {
        return lightForSlot(nft.tokenSlot(tokenId));
    }

    function lightForSlot(uint256 slot) public pure returns (uint256) {
        require(slot < HARD_MAX_SUPPLY, "bad slot");
        if (slot < ORIGIN_SLOT_COUNT) return ORIGIN_LIGHT;

        uint256 roll = _rarityRoll(slot);
        if (roll >= MYTHIC_THRESHOLD) return MYTHIC_LIGHT;
        if (roll >= EPIC_THRESHOLD) return EPIC_LIGHT;
        if (roll >= RARE_THRESHOLD) return RARE_LIGHT;
        return COMMON_LIGHT;
    }

    function _receiveEthFees(uint256 amount) internal {
        require(amount > 0, "no value");
        uint256 ownerAmount = (amount * OWNER_SHARE_BPS) / BPS;
        uint256 holderAmount = amount - ownerAmount;
        ownerEthClaimable += ownerAmount;
        pendingHolderEth += holderAmount;
        emit FeesReceived(msg.sender, address(0), amount, ownerAmount, holderAmount);
    }

    function _syncWethUnsafe() internal {
        uint256 currentBalance = weth.balanceOf(address(this));
        if (currentBalance <= accountedWethBalance) return;

        uint256 amount = currentBalance - accountedWethBalance;
        accountedWethBalance = currentBalance;

        uint256 ownerAmount = (amount * OWNER_SHARE_BPS) / BPS;
        uint256 holderAmount = amount - ownerAmount;
        ownerWethClaimable += ownerAmount;
        pendingHolderWeth += holderAmount;
        emit FeesReceived(msg.sender, address(weth), amount, ownerAmount, holderAmount);
    }

    function _pendingAccEthPerLight() internal view returns (uint256) {
        if (totalLight == 0) return accEthPerLight;
        uint256 total = pendingHolderEth + undistributedEth;
        if (total == 0) return accEthPerLight;
        return accEthPerLight + ((total * ACC_SCALE) / totalLight);
    }

    function _syncedAccWethPerLight() internal view returns (uint256) {
        uint256 total = pendingHolderWeth + undistributedWeth;
        if (totalLight == 0) return accWethPerLight;
        uint256 currentBalance = weth.balanceOf(address(this));
        if (currentBalance > accountedWethBalance) {
            uint256 amount = currentBalance - accountedWethBalance;
            total += amount - ((amount * OWNER_SHARE_BPS) / BPS);
        }
        if (total == 0) return accWethPerLight;
        return accWethPerLight + ((total * ACC_SCALE) / totalLight);
    }

    function _checkpointPending() internal {
        _checkpointEth();
        _checkpointWeth();
    }

    function _checkpointEth() internal {
        uint256 total = pendingHolderEth + undistributedEth;
        if (total == 0) return;
        pendingHolderEth = 0;
        if (totalLight == 0) {
            undistributedEth = total;
            return;
        }
        uint256 rewardPerLight = (total * ACC_SCALE) / totalLight;
        uint256 distributed = (rewardPerLight * totalLight) / ACC_SCALE;
        undistributedEth = total - distributed;
        accEthPerLight += rewardPerLight;
    }

    function _checkpointWeth() internal {
        uint256 total = pendingHolderWeth + undistributedWeth;
        if (total == 0) return;
        pendingHolderWeth = 0;
        if (totalLight == 0) {
            undistributedWeth = total;
            return;
        }
        uint256 rewardPerLight = (total * ACC_SCALE) / totalLight;
        uint256 distributed = (rewardPerLight * totalLight) / ACC_SCALE;
        undistributedWeth = total - distributed;
        accWethPerLight += rewardPerLight;
    }

    function _rarityRoll(uint256 slot) internal pure returns (uint256) {
        uint256 hash = _raritySeed(slot);
        unchecked {
            uint256 state = (hash + 0x6D2B79F5) & 0xffffffff;
            uint256 value = state;
            value = _imul32(value ^ (value >> 15), value | 1);
            value = (value ^ (value + _imul32(value ^ (value >> 7), value | 61))) & 0xffffffff;
            return (value ^ (value >> 14)) & 0xffffffff;
        }
    }

    function _raritySeed(uint256 slot) internal pure returns (uint256 hash) {
        unchecked {
            hash = 2_166_136_261;
            bytes15 prefix = "metadata-rarity";
            for (uint256 index = 0; index < 15; index += 1) {
                hash ^= uint8(prefix[index]);
                hash = _imul32(hash, 16_777_619);
            }
            hash ^= uint8(bytes1(":"));
            hash = _imul32(hash, 16_777_619);

            uint256 divisor = 1;
            uint256 value = slot;
            while (value >= 10) {
                value /= 10;
                divisor *= 10;
            }
            while (divisor > 0) {
                uint256 digit = slot / divisor;
                hash ^= uint8(48 + digit);
                hash = _imul32(hash, 16_777_619);
                slot -= digit * divisor;
                divisor /= 10;
            }
        }
    }

    function _imul32(uint256 left, uint256 right) internal pure returns (uint256) {
        unchecked {
            return (left * right) & 0xffffffff;
        }
    }
}
