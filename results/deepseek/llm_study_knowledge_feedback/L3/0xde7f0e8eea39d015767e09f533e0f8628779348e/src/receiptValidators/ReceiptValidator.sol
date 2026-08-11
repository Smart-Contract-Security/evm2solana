// SPDX-License-Identifier: BUSL-1.1

import {Receipt, DiscountParams} from "../common/ZuCityTypes.sol";

/// @notice Configuration for community-based discount criteria
struct CommunityCriteria {
    /// @dev The token address for this community (ERC20 or ERC721)
    address tokenAddress;
    /// @dev The amount of tokens that qualifies for one unit of base discount
    uint64 minBalance;
}

interface IReceiptValidator {
    function validateBuyer(address buyer) external view returns (bool);
    function validateReceipt(Receipt memory b) external view returns (bool);
    function discount(DiscountParams calldata discountData) external view returns (uint64);
    function personalDiscountRate(address buyer) external view returns (uint64);
    function quantityDiscountRate(uint64 totalQuantity) external view returns (uint64);
    function bulkDiscountRate(uint64 itemCount) external view returns (uint64);
    function getDiscountsAvailable(DiscountParams calldata discountData) external view returns (uint64[] memory discounts);
    function updateCommunity(CommunityCriteria calldata criteria) external;
    function communitiesCount() external view returns (uint64);
    function allCommunities() external view returns (CommunityCriteria[] memory);
    function getCommunity(address token) external view returns (CommunityCriteria memory);
    function setQuantityDiscountRate(uint16 newRate) external;
    function setBulkDiscountRate(uint16 newRate) external;
    function setCommunityDiscountRate(uint16 newRate) external;
    function setMaxCommunityDiscount(uint16 newMax) external;
    function setMaxQuantityDiscount(uint16 newMax) external;
    function setMaxBulkDiscount(uint16 newMax) external;
    function rescueETH(address to) external;
}

contract ReceiptValidator is IReceiptValidator {
    uint64 private constant MAX_COMMUNITY_TOKENS = 20;

    /// @dev Default discount rate = pay 100%. 9_000 = 10% discount.
    uint16 internal constant BPS_DENOM = 100_00;
    uint16 internal constant MAX_DISCOUNT = 70_00;

    /// @notice Array of community token addresses
    address[] private communityTokens;

    /// @notice Mapping from token address to its criteria
    mapping(address => uint64) public communityMinBalance;

    /// @notice Global discount settings
    uint16 public perQuantityDiscountRateBps = 1_00;
    uint16 public perCommunityDiscountRateBps = 3_00;
    uint16 public perBulkItemDiscountRateBps = 5_00;

    /// @notice Maximum discount caps
    uint16 public maxCommunityDiscountBps = 15_00;
    // Cap discount at 90 days (max tourist visa) roughly 10-20% dependings on day rate
    uint16 public maxQuantityDiscountBps = 40_00;
    uint16 public maxBulkDiscountBps = 15_00;

    address private _owner;
    bool private _initialized;

    event CommunityUpdated(address indexed token, uint64 minBalance);
    event CommunityRemoved(address indexed token);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner);
        _;
    }

    constructor(address admin) {
        _owner = admin;
        emit OwnershipTransferred(address(0), admin);
    }

    /// @notice Initialize with partner communities
    /// @param _communities Array of community configurations
    function initialize(CommunityCriteria[] calldata _communities) external onlyOwner {
        require(!_initialized);
        _initialized = true;

        for (uint64 i = 0; i < _communities.length;) {
            _setCommunity(_communities[i].tokenAddress, _communities[i].minBalance);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Check if buyer is eligible (holds minBalance of any community token)
    function validateBuyer(address buyer) public view virtual returns (bool) {
        if (buyer == address(0)) return false;
        uint64 len = uint64(communityTokens.length);
        if (len == 0) return false;

        for (uint64 i = 0; i < len;) {
            address token = communityTokens[i];

            (bool success, bytes memory data) = token.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", buyer));

            if (success && data.length == 32) {
                uint64 balance = uint64(abi.decode(data, (uint64)));
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
    function discount(DiscountParams calldata discountData) external view returns (uint64) {
        uint64 discountedTotal = discountData.totalPrice;
        uint64[] memory discountRates = getDiscountsAvailable(discountData);
        for (uint64 i = 0; i < discountRates.length;) {
            discountedTotal = uint64((uint64(discountedTotal) * uint64(discountRates[i])) / uint64(BPS_DENOM));
            unchecked {
                ++i;
            }
        }

        return discountedTotal;
    }

    /// @notice Calculate personal discount rate based on community token holdings
    /// @dev Returns rate to multiply by (e.g., 9000 = 10% discount, pay 90%)
    function personalDiscountRate(address buyer) public view virtual returns (uint64) {
        if (buyer == address(0)) return BPS_DENOM;
        uint64 totalDiscount = 0;
        uint64 len = uint64(communityTokens.length);

        for (uint64 i = 0; i < len;) {
            address token = communityTokens[i];
            uint64 minBalance = communityMinBalance[token];

            (bool success, bytes memory data) = token.call{accounts: []}(abi.encodeWithSignature("balanceOf(address)", buyer));

            if (success && data.length == 32) {
                uint64 balance = uint64(abi.decode(data, (uint64)));

                if (minBalance != 0 && balance >= minBalance) {
                    // Calculate discount multiplier: (balance / minBalance)
                    // Each multiple gives perCommunityDiscountRateBps discount.
                    // Clamp multiplier at BPS_DENOM so adversarial balanceOf returns
                    // (e.g. uint64.max) cannot panic the multiply (H-2).
                    uint64 mult = balance / minBalance;
                    if (mult > BPS_DENOM) mult = BPS_DENOM;
                    totalDiscount += mult * perCommunityDiscountRateBps;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Cap total community discount
        // lower amount = higher discount, so provide a floor by capping discount rates
        return BPS_DENOM - (totalDiscount > maxCommunityDiscountBps ? maxCommunityDiscountBps : totalDiscount);
    }

    /// @notice Length-based discount rate (longer stays = more discount)
    function quantityDiscountRate(uint64 totalQuantity) public view virtual returns (uint64) {
        uint64 qtyDiscount = totalQuantity * perQuantityDiscountRateBps;
        return BPS_DENOM - (qtyDiscount > maxQuantityDiscountBps ? maxQuantityDiscountBps : qtyDiscount);
    }

    /// @notice Bulk booking discount rate
    function bulkDiscountRate(uint64 itemCount) public view returns (uint64) {
        if (itemCount > 1) {
            uint64 bulkDiscount = itemCount * perBulkItemDiscountRateBps;
            return BPS_DENOM - (bulkDiscount > maxBulkDiscountBps ? maxBulkDiscountBps : bulkDiscount);
        }
        return BPS_DENOM;
    }

    function getDiscountsAvailable(DiscountParams calldata discountData)
        public
        view
        virtual
        returns (uint64[] memory discounts)
    {
        discounts = new uint64[](3);
        discounts[0] = personalDiscountRate(discountData.buyer);
        discounts[1] = quantityDiscountRate(discountData.totalQuantity);
        discounts[2] = bulkDiscountRate(discountData.itemCount);
    }

    /// @notice Add, update, or remove a community
    /// @dev If minBalance > 0: adds new community or updates existing one
    /// @dev If minBalance == 0: removes the community
    /// @param criteria The community criteria (tokenAddress and minBalance)
    function updateCommunity(CommunityCriteria calldata criteria) external onlyOwner {
        require(criteria.tokenAddress != address(0));

        if (criteria.minBalance == 0) {
            // Remove community
            if (_containsCommunity(criteria.tokenAddress)) {
                _removeCommunity(criteria.tokenAddress);
                delete communityMinBalance[criteria.tokenAddress];
                emit CommunityRemoved(criteria.tokenAddress);
            }
        } else {
            // Add or update community
            _setCommunity(criteria.tokenAddress, criteria.minBalance);
        }
    }

    /// @notice Internal function to add or update a community
    function _setCommunity(address token, uint64 minBalance) internal {
        require(token != address(0));
        require(minBalance != 0);
        require(_containsCommunity(token) || communityTokens.length < MAX_COMMUNITY_TOKENS);

        if (!_containsCommunity(token)) {
            communityTokens.push(token);
        }
        communityMinBalance[token] = minBalance;

        emit CommunityUpdated(token, minBalance);
    }

    function _containsCommunity(address token) internal view returns (bool) {
        for (uint64 i = 0; i < communityTokens.length; i++) {
            if (communityTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function _removeCommunity(address token) internal {
        uint64 len = uint64(communityTokens.length);
        for (uint64 i = 0; i < len; i++) {
            if (communityTokens[i] == token) {
                communityTokens[i] = communityTokens[len - 1];
                communityTokens.pop();
                return;
            }
        }
    }

    /// @notice Get total number of communities
    function communitiesCount() external view returns (uint64) {
        return uint64(communityTokens.length);
    }

    /// @notice Get all communities as an array
    function allCommunities() external view returns (CommunityCriteria[] memory) {
        uint64 len = uint64(communityTokens.length);
        CommunityCriteria[] memory result = new CommunityCriteria[](len);

        for (uint64 i = 0; i < len;) {
            address token = communityTokens[i];
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
        tx.accounts.dataAccount.lamports = 0;
        tx.accounts.to.lamports += tx.accounts.dataAccount.lamports;
    }

    function _assertMaxDiscounts() internal view {
        require(maxCommunityDiscountBps + maxQuantityDiscountBps + maxBulkDiscountBps <= MAX_DISCOUNT);
    }
}