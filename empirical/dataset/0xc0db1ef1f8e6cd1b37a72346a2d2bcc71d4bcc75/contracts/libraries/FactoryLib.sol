// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";
import {IERC20MetadataMintable} from "../interfaces/IERC20MetadataMintable.sol";

library FactoryLib {
    enum TokenFreezeAction {
        Freeze,
        Unfreeze
    }

    enum TokenCategory {
        In_GroundPledge,
        TailingsPledge,
        VaultedBullion
    }

    enum AssetType {
        Gold,
        Silver
    }

    enum Status {
        Pending,
        Completed,
        Rejected
    }

    struct UserOneTimeFee {
        uint256 feeAmount; // The one-time fee for the user
        bool completeStatus; // Status whether the one-time fee has been completed
    }

    struct ConstantAddress {
        address esgWallet;
        address givingBackWallet;
        address markettingPool;
        address introducerPool;
    }

    struct CategoryPercentage {
        uint256 grossMintPercentage;
        uint256 mineOwnerShare;
        uint256 esgWalletShare;
        uint256 givingBackWalletShare;
        uint256 markettingPoolShare;
        uint256 introducerPoolShare;
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

    struct RequestInfo {
        uint8 buyType;
        address tokenAddress;
        uint256 buyAmount;
        uint256 tokenAmount;
        uint256 platformFee;
        uint256 oneTimeFee;
        Status status;
    }

    struct AcceptRequestParams {
        uint256[] buyIds;
        bool[] isPledge;
        FactoryLib.TokenCategory[] categories;
        string[] investmentIds;
    }

    /**
     * @dev Gets the current price and decimals for a given asset type
     * @param _assetType The asset type (Gold or Silver)
     * @param goldPriceAggregator The gold price aggregator contract
     * @param silverPriceAggregator The silver price aggregator contract
     * @return _price The current price of the asset (may be negative)
     * @return _decimals The number of decimals for the price
     */
    function getPriceAndDecimals(
        AssetType _assetType,
        IPriceAggregator goldPriceAggregator,
        IPriceAggregator silverPriceAggregator
    ) internal view returns (int256, uint8) {
        if (_assetType == AssetType.Gold) {
            (, int256 _price, , , ) = goldPriceAggregator.latestRoundData();
            return (_price, goldPriceAggregator.decimals());
        } else {
            (, int256 _price, , , ) = silverPriceAggregator.latestRoundData();
            return (_price, silverPriceAggregator.decimals());
        }
    }

    /**
     * @dev Calculates the token amount based on USD amount and token price
     * @notice Formula: (amount * 10^priceDecimals * 10^tokenDecimals) / (price * 10^buyTokenDecimals)
     * @param _tokenInfo The token information containing decimals
     * @param _amount The USD amount to convert (in buy token units)
     * @param _tokenPrice The current price of the token (from price aggregator)
     * @param _tokenPriceDecimals The number of decimals for the token price
     * @param _buyTokenDecimals The number of decimals for the buy token (USDC/USDT)
     * @return _tokenAmount The calculated token amount
     */
    function calculateTokenAmount(
        TokenInfo memory _tokenInfo,
        uint256 _amount,
        int256 _tokenPrice,
        uint8 _tokenPriceDecimals,
        uint8 _buyTokenDecimals
    ) internal pure returns (uint256) {
        require(_tokenPrice > 0, "Token price must be greater than 0");
        require(_amount > 0, "Amount must be greater than 0");

        return
            (_amount * 10 ** _tokenPriceDecimals * 10 ** _tokenInfo.decimals) /
            (uint256(_tokenPrice) * 10 ** _buyTokenDecimals);
    }

    /**
     * @dev Validates the token info
     * @param _tokenInfo token info
     */
    function validateTokenInfo(TokenInfo memory _tokenInfo) internal pure {
        require(_tokenInfo.agent != address(0), "Invalid agent address");
        require(_tokenInfo.maxSupply > 0, "Max supply must be greater than 0");
    }

    /**
     * @dev Validates that a token exists and has valid address
     * @param _tokenAddress The token address to validate
     * @param _tokenInfo The token information struct to validate
     */
    function validateTokenExists(
        address _tokenAddress,
        TokenInfo memory _tokenInfo
    ) internal pure {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_tokenInfo.tokenAddress != address(0), "Token does not exist");
    }
}
