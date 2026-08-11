// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FactoryLib} from "../libraries/FactoryLib.sol";
import "./IERC20MetadataMintable.sol";

interface IFactory {
    event PropertyDeployed(
        uint256 indexed propertyId,
        address indexed propertyAddress,
        string offeringId
    );

    event TokensBought(
        address indexed user,
        address indexed tokenAddress,
        uint256 buyId,
        uint256 buyAmount,
        uint256 tokenAmount,
        uint256 platformFee,
        string investmentId
    );

    event MintRequestedAccepted(
        address indexed tokenAddress,
        address indexed user,
        uint256 buyId,
        uint256 tokenAmount,
        string investmentId
    );

    event MintRequestedRejected(
        address indexed tokenAddress,
        address indexed user,
        uint256 buyId,
        string investmentId
    );

    event TokenAction(
        address indexed userAddress,
        address indexed tokenAddress,
        uint256 amount,
        uint8 action
    );

    event AccountFrozenUpdate(
        address indexed tokenAddress,
        FactoryLib.TokenFreezeAction action,
        address indexed user
    );

    event ForcedTokenTransferred(
        address indexed lostWallet,
        address indexed newWallet,
        address tokenAddress,
        uint256 tokenAmount,
        string transferId
    );

    event TokensMinted(
        address indexed tokenAddress,
        address indexed toAddress,
        uint256 amount
    );

    event TokensBurned(
        address indexed tokenAddress,
        address indexed fromAddress,
        uint256 amount
    );

    event OfferingFeeUpdated(
        address indexed tokenAddress,
        uint256 newOfferingFee
    );

    event TokenCategoryPercentageUpdated(
        FactoryLib.CategoryPercentage[] categoryPercentages,
        address tokenAddress
    );

    event ConstantAddressesUpdated(
        FactoryLib.ConstantAddress constantAddresses,
        address tokenAddress
    );

    event TokenMaxSupplyUpdated(address indexed tokenAddress, uint256 amount);

    function emitFrozenTokens(
        FactoryLib.TokenFreezeAction action,
        address user,
        uint256 amount
    ) external;

    function emitFrozenAccount(
        FactoryLib.TokenFreezeAction action,
        address user
    ) external;

    function emitForceTransfer(
        address from,
        address to,
        uint256 amount,
        string memory transferId
    ) external;

    function emitMintRequested(address toAddress, uint256 amount) external;

    function emitBurnRequested(address fromAddress, uint256 amount) external;

    function getTokenInfo(
        address tokenAddress
    ) external view returns (FactoryLib.TokenInfo memory);

    function updateTokenBought(address tokenAddress, uint256 amount) external;

    function updateTokenLocked(
        address tokenAddress,
        uint256 amount,
        bool add
    ) external;

    function transferCategoryShares(
        FactoryLib.TokenCategory category,
        address user,
        address tokenAddress,
        uint256 amount
    ) external returns (FactoryLib.CategoryPercentage memory);

    function transferTokens(
        IERC20MetadataMintable token,
        address to,
        uint256 amount
    ) external;

    function calculateGrossMintAmount(
        FactoryLib.TokenCategory category,
        address tokenAddress,
        uint256 baseAmount
    ) external view returns (uint256);

    function calculateCategoryShares(
        FactoryLib.TokenCategory category,
        uint256 amount,
        address tokenAddress
    ) external view returns (uint256, uint256, uint256, uint256, uint256);
}
