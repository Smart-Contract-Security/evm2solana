// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FactoryLib} from "../libraries/FactoryLib.sol";

interface IRequestManager {
    event TokensBought(
        address indexed user,
        address indexed tokenAddress,
        uint256 buyId,
        uint256 buyAmount,
        uint256 tokenAmount,
        uint256 feesAmount,
        uint256 oneTimeFee,
        string investmentId
    );

    event MintRequestAccepted(
        address indexed tokenAddress,
        address indexed user,
        uint256 buyId,
        uint256 tokenAmount,
        string investmentId,
        FactoryLib.CategoryPercentage categoryPercentage
    );

    event MintRequestRejected(
        address indexed tokenAddress,
        address indexed user,
        uint256 buyId,
        string investmentId
    );

    function requestTokens(
        uint8 buyType,
        uint256 buyAmount,
        address tokenAddress,
        string memory investmentId
    ) external;

    function acceptBuyRequest(
        address[] calldata users,
        address[] calldata tokenAddresses,
        uint256[] calldata tokenAmounts,
        FactoryLib.AcceptRequestParams calldata acceptRequestParams
    ) external;

    function rejectBuyRequest(
        address[] calldata users,
        address[] calldata tokenAddresses,
        uint256[] calldata buyIds,
        string[] calldata investmentIds
    ) external;

    function getUserRequestCount(
        address user,
        address tokenAddress
    ) external view returns (uint256);

    function getRequestInfo(
        address user,
        address tokenAddress,
        uint256 buyId
    ) external view returns (FactoryLib.RequestInfo memory);
}
