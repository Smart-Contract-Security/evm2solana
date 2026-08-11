// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title CompositePriceFeed
/// @notice Combines two Chainlink feeds sharing a common denominator into a
///         single AggregatorV3Interface. Given a baseFeed `BASE/COMMON` and a
///         quoteFeed `QUOTE/COMMON`, `latestRoundData()` returns the implied
///         `BASE/QUOTE` rate (e.g. ETH/USD + GBP/USD -> ETH/GBP).
/// @dev    Output decimals follow `baseFeed.decimals()`. `updatedAt` returns
///         the older of the two underlying feed timestamps so downstream
///         staleness checks remain meaningful.
contract CompositePriceFeed is AggregatorV3Interface {
    AggregatorV3Interface public immutable baseFeed;
    AggregatorV3Interface public immutable quoteFeed;

    uint8 private immutable _decimals;
    uint256 private immutable _quoteScale;
    string private _description;

    error InvalidBaseAnswer();
    error InvalidQuoteAnswer();
    error HistoricalRoundsNotSupported();

    constructor(address baseFeed_, address quoteFeed_, string memory description_) {
        baseFeed = AggregatorV3Interface(baseFeed_);
        quoteFeed = AggregatorV3Interface(quoteFeed_);
        _decimals = AggregatorV3Interface(baseFeed_).decimals();
        _quoteScale = 10 ** uint256(AggregatorV3Interface(quoteFeed_).decimals());
        _description = description_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint80 bRound, int256 bAns, uint256 bStarted, uint256 bUpdated, uint80 bAnsweredIn) = baseFeed.latestRoundData();
        (, int256 qAns, uint256 qStarted, uint256 qUpdated, ) = quoteFeed.latestRoundData();
        if (bAns <= 0) revert InvalidBaseAnswer();
        if (qAns <= 0) revert InvalidQuoteAnswer();

        // base has bDec decimals, quote has qDec decimals.
        // (bAns * 10^qDec) / qAns => result with bDec decimals.
        answer = (bAns * int256(_quoteScale)) / qAns;
        roundId = bRound;
        startedAt = bStarted < qStarted ? bStarted : qStarted;
        updatedAt = bUpdated < qUpdated ? bUpdated : qUpdated;
        answeredInRound = bAnsweredIn;
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert HistoricalRoundsNotSupported();
    }
}
