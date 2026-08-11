// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracle {
    struct PriceData {
        uint128 priceUSDC;
        uint64 updatedAt;
    }

    event PriceUpdated(address indexed token, uint128 priceUSDC, uint64 updatedAt);
    event FeederSet(address indexed feeder);

    error UnsetPrice(address token);
    error ZeroPrice(address token);
    error LengthMismatch();

    function setPrice(address[] calldata tokens, uint128[] calldata prices) external;
    function getPrice(address token) external view returns (uint256);
    function getPriceData(address token) external view returns (PriceData memory);
    function setFeeder(address feeder) external;
}
