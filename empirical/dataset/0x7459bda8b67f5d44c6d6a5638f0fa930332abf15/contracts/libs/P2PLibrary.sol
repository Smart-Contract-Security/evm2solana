//SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";

library P2PLibrary {
    enum PropertyType {
        ERC20,
        ERC3643
    }

    enum OrderStatus {
        PENDING,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED
    }

    enum BuyType {
        USDT,
        USDC
    }

    enum AssetType {
        Gold,
        Silver
    }

    struct TokenInfo {
        address agent;
        address tokenAddress;
        uint8 decimals;
        uint256 minimumInvestment;
        uint256 maximumInvestment;
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 locked;
        uint256 bought;
        uint256 frozenTokens;
        uint256 platformFee;
        AssetType assetType;
    }

    struct BuyOffer {
        uint256 price; // price per token
        uint256 totalTokens; // total tokens user wants to buy
        uint256 filledTokens; // tokens already bought.....
        uint256 fee; // fee charged for the order.....
        uint256 paymentAmount; // total payment required
        uint256 remainingPaymentAmount; // total payment required.....
        uint256 propertyId; // property identifier
        uint64 feePercentage; // fee percentage
        BuyType paymentToken; // payment token (USDT / USDC)
        PropertyType propertyType; // ERC20 / ERC3643
        OrderStatus status; // PENDING / PARTIALLY_FILLED / FILLED / CANCELLED.....
        address maker; // order creator
        address tokenAddress; // property token address
    }

    struct SellOffer {
        uint256 price; // price per token
        uint256 totalTokens; // total tokens user wants to sell
        uint256 filledTokens; // tokens already sold
        uint256 fee; // fee charged for the order
        uint256 propertyId; // property identifier
        uint64 feePercentage; // fee percentage
        BuyType paymentToken; // payment token (USDT / USDC)
        PropertyType propertyType; // ERC20 / ERC3643
        OrderStatus status; // PENDING / PARTIALLY_FILLED / FILLED / CANCELLED
        address maker; // order creator
        address tokenAddress; // property token address
    }

    struct PropertyData {
        uint256 minimumBuy; // Minimum buy amount allowed for the property (in USD)
        uint256 maximumBuy; // Maximum buy amount allowed for the property (in USD)
        uint256 totalSupply; // Total supply of the property tokens
        uint256 bought; // Total amount of property tokens bought by users
        uint256 locked; // Amount of property tokens that are locked
        uint256 frozenTokens; // Amount of property tokens that are frozen
        uint256 maxHold; // Maximum tokens a user can hold for this property
        uint128 price; // Price of the property token (with decimals)
        uint8 decimals; // This is token decimals 
        address agent; // Address of the agent responsible for the property
        address token; // Token address for the property
        address irAddress; // Address for the Investor Relations
        address mcAddress; // Address for the management company
        address propertyOwner; // Address of the property owner
    }
}
