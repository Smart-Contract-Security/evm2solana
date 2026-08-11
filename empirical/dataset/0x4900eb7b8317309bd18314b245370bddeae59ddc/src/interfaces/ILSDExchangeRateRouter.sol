// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./ILSDAdapter.sol";

interface ILSDExchangeRateRouter {
    struct BatchResult {
        address lsdToken;
        bool success;
        ILSDAdapter.ExchangeRateInfo info;
        string errorMessage;
    }

    // ============ Admin ============

    function registerAdapter(address lsdToken, address adapter) external;
    function registerAdapterBatch(address[] calldata lsdTokens, address adapter) external;
    function updateAdapter(address lsdToken, address newAdapter) external;
    function updateAdapterBatch(address[] calldata lsdTokens, address newAdapter) external;
    function removeAdapter(address lsdToken) external;

    // ============ Pause control ============

    function pause() external;
    function unpause() external;
    function pauseAdapter(address adapter) external;
    function unpauseAdapter(address adapter) external;
    function isAdapterPaused(address adapter) external view returns (bool);

    // ============ Registry View ============

    function getAdapter(address lsdToken) external view returns (address);
    function isLSDRegistered(address lsdToken) external view returns (bool);
    function getAdapterCount() external view returns (uint256);
    function getUniqueAdapterCount() external view returns (uint256);
    function getAllRegisteredLSDs() external view returns (address[] memory);
    function getAllAdapters() external view returns (address[] memory);
    function getRegisteredLSDsPaginated(uint256 offset, uint256 limit)
        external view returns (address[] memory lsdTokens, uint256 total);

    // ============ Single Query ============

    function getExchangeRate(address lsdToken) external view returns (ILSDAdapter.ExchangeRateInfo memory);
    function convertToUnderlying(address lsdToken, uint256 lsdAmount)
        external view returns (uint256 underlyingAmount, ILSDAdapter.ExchangeRateInfo memory info);

    // ============ Recursive Query ============

    function getExchangeRateRecursive(address lsdToken) external view returns (ILSDAdapter.ExchangeRateInfo memory);
    function convertToUnderlyingRecursive(address lsdToken, uint256 lsdAmount)
        external view returns (uint256 underlyingAmount, ILSDAdapter.ExchangeRateInfo memory info);

    // ============ Batch Query ============

    function batchGetExchangeRates(address[] calldata lsdTokens) external view returns (BatchResult[] memory);
    function batchConvertToUnderlying(address[] calldata lsdTokens, uint256[] calldata amounts)
        external view returns (uint256[] memory underlyingAmounts, BatchResult[] memory results);
}
