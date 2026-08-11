// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.29;

import {IReceiptValidator} from "../interfaces/IReceiptValidator.sol";
import {Receipt, DiscountParams} from "../common/ZuCityTypes.sol";
import {EnumerableSetLib, AddressSet} from "solady/utils/g/EnumerableSetLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Configuration for community-based discount criteria
struct CommunityCriteria {
    /// @dev The token address for this community (ERC20 or ERC721)
    address tokenAddress;
    /// @dev The amount of tokens that qualifies for one unit of base discount
    uint256 minBalance;
}

contract ReceiptValidator is IReceiptValidator, Ownable {
    using EnumerableSetLib for AddressSet;
    uint256 private constant MAX_COMMUNITY_TOKENS = 20;

    /// @dev Default discount rate = pay 100%. 9_000 = 10% discount.
    uint16 internal constant BPS_DENOM = 100_00;
    uint16 internal constant MAX_DISCOUNT = 70_00;

    /// @notice Set of all community token addresses
    AddressSet private communityTokens;

    /// @notice Mapping from token address to its criteria
    mapping(address => uint256) public communityMinBalance;

    /// @notice Global discount settings
    uint16 public perQuantityDiscountRateBps = 1_00;
    uint16 public perCommunityDiscountRateBps = 3_00;
    uint16 public perBulkItemDiscountRateBps = 5_00;

    /// @notice Maximum discount caps
    uint16 public maxCommunityDiscountBps = 15_00;
    // Cap discount at 90 days (max tourist visa) roughly 10-20% dependings on day rate
    uint16 public maxQuantityDiscountBps = 40_00;
    uint16 public maxBulkDiscountBps = 15_00;

    bool private _initialized;

    error InvalidCommunity();
    error MaxDiscountExceeded();
    error MaxCommunitiesExceeded();

    event CommunityUpdated(address indexed token, uint256 minBalance);
    event CommunityRemoved(address indexed token);

    constructor(address admin) {
        _initializeOwner(admin);
    }

    /// @notice Initialize with partner communities
    /// @param _communities Array of community configurations
    function initialize(CommunityCriteria[] calldata _communities) external onlyOwner {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        for (uint256 i = 0; i < _communities.length;) {
            _setCommunity(_communities[i].tokenAddress, _communities[i].minBalance);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Check if buyer is eligible (holds minBalance of any community token)
    function validateBuyer(address buyer) public view virtual returns (bool) {
        if (buyer == address(0)) return false;
        uint256 len = communityTokens.length();
        if (len == 0) return false;

        for (uint256 i = 0; i < len;) {
            address token = communityTokens.at(i);

            (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", buyer));

            if (success && data.length == 32) {
                uint256 balance = abi.decode(data, (uint256));
                if (balance >= communityMinBalance[token]) {
                    return true;
                }
            }

            unchecked {
                ++i;
            }
        }

        return false;
    }

    /// @notice Check if buyer is eligible (holds minBalance of any community token)
    function validateReceipt(Receipt memory b) public view virtual returns (bool) {
        // default dont care what people buy, just who is buying
        return true;
    }

    /// @notice Calculate bulk discount for multiple items
    /// @return finalDiscountedPrice - price of entire order after deducting all discounts
    function discount(DiscountParams calldata discountData) external view returns (uint256) {
        uint256 discountedTotal = discountData.totalPrice;
        uint256[] memory discountRates = getDiscountsAvailable(discountData);
        for (uint256 i = 0; i < discountRates.length;) {
            discountedTotal = (discountedTotal * discountRates[i]) / BPS_DENOM;
            unchecked {
                ++i;
            }
        }

        return discountedTotal;
    }

    /// @notice Calculate personal discount rate based on community token holdings
    /// @dev Returns rate to multiply by (e.g., 9000 = 10% discount, pay 90%)
    function personalDiscountRate(address buyer) public view virtual returns (uint256) {
        if (buyer == address(0)) return BPS_DENOM;
        uint256 totalDiscount = 0;
        uint256 len = communityTokens.length();

        for (uint256 i = 0; i < len;) {
            address token = communityTokens.at(i);
            uint256 minBalance = communityMinBalance[token];

            (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", buyer));

            if (success && data.length == 32) {
                unchecked {

                    uint256 balance = abi.decode(data, (uint256));

                    if (minBalance != 0 && balance >= minBalance) {
                        // Calculate discount multiplier: (balance / minBalance)
                        // Each multiple gives perCommunityDiscountRateBps discount.
                        // Clamp multiplier at BPS_DENOM so adversarial balanceOf returns
                        // (e.g. uint256.max) cannot panic the multiply (H-2).
                        uint256 mult = balance / minBalance;
                        if (mult > BPS_DENOM) mult = BPS_DENOM;
                        totalDiscount += mult * perCommunityDiscountRateBps;
                    }
                    ++i;
                }
            }
        }

        // Cap total community discount
        // lower amount = higher discount, so provide a floor by capping discount rates
        return BPS_DENOM - (totalDiscount > maxCommunityDiscountBps ? maxCommunityDiscountBps : totalDiscount);
    }

    /// @notice Length-based discount rate (longer stays = more discount)
    function quantityDiscountRate(uint256 totalQuantity) public view virtual returns (uint256) {
        uint256 qtyDiscount = totalQuantity * perQuantityDiscountRateBps;
        return BPS_DENOM - (qtyDiscount > maxQuantityDiscountBps ? maxQuantityDiscountBps : qtyDiscount);
    }

    /// @notice Bulk booking discount rate
    function bulkDiscountRate(uint256 itemCount) public view returns (uint256) {
        if (itemCount > 1) {
            uint256 bulkDiscount = itemCount * perBulkItemDiscountRateBps;
            return BPS_DENOM - (bulkDiscount > maxBulkDiscountBps ? maxBulkDiscountBps : bulkDiscount);
        }
        return BPS_DENOM;
    }

    function getDiscountsAvailable(DiscountParams calldata discountData)
        public
        view
        virtual
        returns (uint256[] memory discounts)
    {
        discounts = new uint256[](3);
        discounts[0] = personalDiscountRate(discountData.buyer);
        discounts[1] = quantityDiscountRate(discountData.totalQuantity);
        discounts[2] = bulkDiscountRate(discountData.itemCount);
    }

    /// @notice Add, update, or remove a community
    /// @dev If minBalance > 0: adds new community or updates existing one
    /// @dev If minBalance == 0: removes the community
    /// @param criteria The community criteria (tokenAddress and minBalance)
    function updateCommunity(CommunityCriteria calldata criteria) external onlyOwner {
        if (criteria.tokenAddress == address(0)) revert InvalidCommunity();

        if (criteria.minBalance == 0) {
            // Remove community
            if (communityTokens.contains(criteria.tokenAddress)) {
                communityTokens.remove(criteria.tokenAddress);
                delete communityMinBalance[criteria.tokenAddress];
                emit CommunityRemoved(criteria.tokenAddress);
            }
        } else {
            // Add or update community
            _setCommunity(criteria.tokenAddress, criteria.minBalance);
        }
    }

    /// @notice Internal function to add or update a community
    function _setCommunity(address token, uint256 minBalance) internal {
        if (token == address(0)) revert InvalidCommunity();
        if (minBalance == 0) revert InvalidCommunity();
        if (!communityTokens.contains(token) && communityTokens.length() >= MAX_COMMUNITY_TOKENS) {
            revert MaxCommunitiesExceeded();
        }

        communityTokens.add(token); // No-op if already exists
        communityMinBalance[token] = minBalance;

        emit CommunityUpdated(token, minBalance);
    }

    /// @notice Get total number of communities
    function communitiesCount() external view returns (uint256) {
        return communityTokens.length();
    }

    /// @notice Get all communities as an array
    function allCommunities() external view returns (CommunityCriteria[] memory) {
        uint256 len = communityTokens.length();
        CommunityCriteria[] memory result = new CommunityCriteria[](len);

        for (uint256 i = 0; i < len;) {
            address token = communityTokens.at(i);
            result[i] = CommunityCriteria({tokenAddress: token, minBalance: communityMinBalance[token]});
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /// @notice Get community criteria by token address
    function getCommunity(address token) external view returns (CommunityCriteria memory) {
        return CommunityCriteria({tokenAddress: token, minBalance: communityMinBalance[token]});
    }

    /// @notice Update length discount rate.
    /// @dev Per-rate setters intentionally accept any uint16. Oversized rates are harmless:
    ///      the corresponding max*DiscountBps floor (applied in quantityDiscountRate /
    ///      bulkDiscountRate / personalDiscountRate) clamps the effective discount.
    function setQuantityDiscountRate(uint16 newRate) external onlyOwner {
        perQuantityDiscountRateBps = newRate;
    }

    /// @notice Update bulk discount rate.
    /// @dev See setQuantityDiscountRate — max*DiscountBps absorbs oversized inputs.
    function setBulkDiscountRate(uint16 newRate) external onlyOwner {
        perBulkItemDiscountRateBps = newRate;
    }

    /// @notice Update per-partner discount rate.
    /// @dev See setQuantityDiscountRate — max*DiscountBps absorbs oversized inputs.
    function setCommunityDiscountRate(uint16 newRate) external onlyOwner {
        perCommunityDiscountRateBps = newRate;
    }

    /// @notice Update max total community discount
    function setMaxCommunityDiscount(uint16 newMax) external onlyOwner {
        maxCommunityDiscountBps = newMax;
        _assertMaxDiscounts();
    }

    /// @notice Update max length discount
    function setMaxQuantityDiscount(uint16 newMax) external onlyOwner {
        maxQuantityDiscountBps = newMax;
        _assertMaxDiscounts();
    }

    /// @notice Update max bulk discount
    function setMaxBulkDiscount(uint16 newMax) external onlyOwner {
        maxBulkDiscountBps = newMax;
        _assertMaxDiscounts();
    }

    /// @notice Rescue ETH accidentally sent to the contract
    function rescueETH(address to) external onlyOwner {
        SafeTransferLib.safeTransferAllETH(to);
    }

    function _assertMaxDiscounts() internal view {
        if (maxCommunityDiscountBps + maxQuantityDiscountBps + maxBulkDiscountBps > MAX_DISCOUNT) {
            revert MaxDiscountExceeded();
        }
    }
}
