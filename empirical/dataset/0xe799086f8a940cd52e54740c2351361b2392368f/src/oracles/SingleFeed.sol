// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/AggregatorV3Interface.sol";

contract SingleFeed {
    address immutable feed;

    uint256 public targetDecimals = 18;
    uint256 public feedDecimals;

    constructor(address _feed) {
        feed = _feed;
        feedDecimals = AggregatorV3Interface(feed).decimals();
    }

    function getPrice() public view returns (uint256) {
        (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
        require(answer >= 0, "amount should be positive");
        uint256 price = uint256(answer);

        if (feedDecimals < targetDecimals) {
            price = price * (10 ** (targetDecimals - feedDecimals));
        } else if (targetDecimals < feedDecimals) {
            price = price / (10 ** (feedDecimals - targetDecimals));
        }

        return price;
    }
}
