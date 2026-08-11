// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUnidrawNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function tokenDNA(uint256 tokenId) external view returns (uint256);
}

contract DRAWClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant COMMON_REWARD = 1_000 ether;
    uint256 public constant RARE_REWARD = 2_000 ether;
    uint256 public constant LEGENDARY_REWARD = 5_000 ether;
    uint256 public constant MYTHIC_REWARD = 10_000 ether;

    enum Rarity {
        Common,
        Rare,
        Legendary,
        Mythic
    }

    IUnidrawNFT public immutable unidrawNFT;
    IERC20 public immutable drawToken;

    address public feeReceiver;
    uint256 public serviceFee;

    mapping(uint256 tokenId => bool claimed) public claimedTokenIds;

    event Claimed(address indexed user, uint256[] tokenIds, uint256 amount, uint256 fee);
    event ServiceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    error ZeroAddress();
    error EmptyTokenIds();
    error IncorrectServiceFee(uint256 requiredFee);
    error TokenAlreadyClaimed(uint256 tokenId);
    error NotTokenOwner(uint256 tokenId, address actualOwner);
    error FeeTransferFailed();

    constructor(address unidrawNftAddress, address drawTokenAddress, address initialFeeReceiver, uint256 initialServiceFee)
        Ownable(msg.sender)
    {
        if (unidrawNftAddress == address(0) || drawTokenAddress == address(0) || initialFeeReceiver == address(0)) {
            revert ZeroAddress();
        }

        unidrawNFT = IUnidrawNFT(unidrawNftAddress);
        drawToken = IERC20(drawTokenAddress);
        feeReceiver = initialFeeReceiver;
        serviceFee = initialServiceFee;
    }

    function claim(uint256[] calldata tokenIds) external payable nonReentrant {
        if (tokenIds.length == 0) revert EmptyTokenIds();
        if (msg.value != serviceFee) revert IncorrectServiceFee(serviceFee);

        uint256 amount;
        for (uint256 i = 0; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];
            if (claimedTokenIds[tokenId]) revert TokenAlreadyClaimed(tokenId);

            address actualOwner = unidrawNFT.ownerOf(tokenId);
            if (actualOwner != msg.sender) revert NotTokenOwner(tokenId, actualOwner);

            claimedTokenIds[tokenId] = true;
            amount += rewardForRarity(rarityOfToken(tokenId));

            unchecked {
                i += 1;
            }
        }

        if (msg.value != 0) {
            (bool sent,) = feeReceiver.call{value: msg.value}("");
            if (!sent) revert FeeTransferFailed();
        }

        drawToken.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, tokenIds, amount, msg.value);
    }

    function previewClaim(address user, uint256[] calldata tokenIds)
        external
        view
        returns (
            uint256 totalOwned,
            uint256 totalEligible,
            uint256 totalAlreadyClaimed,
            uint256 totalAmount,
            uint256[4] memory rarityCounts
        )
    {
        for (uint256 i = 0; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];
            if (unidrawNFT.ownerOf(tokenId) == user) {
                totalOwned += 1;

                if (claimedTokenIds[tokenId]) {
                    totalAlreadyClaimed += 1;
                } else {
                    Rarity rarity = rarityOfToken(tokenId);
                    uint256 rarityIndex = uint256(rarity);
                    rarityCounts[rarityIndex] += 1;
                    totalEligible += 1;
                    totalAmount += rewardForRarity(rarity);
                }
            }

            unchecked {
                i += 1;
            }
        }
    }

    function rarityOfToken(uint256 tokenId) public view returns (Rarity) {
        return _rarityFromDNA(unidrawNFT.tokenDNA(tokenId));
    }

    function rewardForToken(uint256 tokenId) external view returns (uint256) {
        return rewardForRarity(rarityOfToken(tokenId));
    }

    function rewardForRarity(Rarity rarity) public pure returns (uint256) {
        if (rarity == Rarity.Rare) return RARE_REWARD;
        if (rarity == Rarity.Legendary) return LEGENDARY_REWARD;
        if (rarity == Rarity.Mythic) return MYTHIC_REWARD;
        return COMMON_REWARD;
    }

    function setServiceFee(uint256 newServiceFee) external onlyOwner {
        uint256 oldFee = serviceFee;
        serviceFee = newServiceFee;
        emit ServiceFeeUpdated(oldFee, newServiceFee);
    }

    function setFeeReceiver(address newFeeReceiver) external onlyOwner {
        if (newFeeReceiver == address(0)) revert ZeroAddress();
        address oldReceiver = feeReceiver;
        feeReceiver = newFeeReceiver;
        emit FeeReceiverUpdated(oldReceiver, newFeeReceiver);
    }

    function withdrawAccidentalETH(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool sent,) = to.call{value: address(this).balance}("");
        if (!sent) revert FeeTransferFailed();
    }

    function _rarityFromDNA(uint256 dna) private pure returns (Rarity) {
        // Matches the deployed Unidraw NFT rarity derivation. Unidraw metadata and tokenTraits
        // are generated from tokenDNA, so the claim contract reads tokenDNA directly instead of
        // attempting expensive onchain parsing of base64 JSON metadata.
        uint256 roll = (dna >> 88) % 10_000;
        if (roll < 7_500) return Rarity.Common;
        if (roll < 9_300) return Rarity.Rare;
        if (roll < 9_900) return Rarity.Legendary;
        return Rarity.Mythic;
    }
}
