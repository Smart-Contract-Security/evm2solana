// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/AggregatorV3Interface.sol";

contract TwoBaseFeeds {
    address private feed1;
    address private feed2;
    uint256 public targetDecimals = 18;
    uint256 public feedsTotalDecimals;

    constructor(address _feed1, address _feed2) {
        feed1 = _feed1;
        feed2 = _feed2;

        feedsTotalDecimals = AggregatorV3Interface(feed1).decimals() + AggregatorV3Interface(feed2).decimals();
    }

    function getPrice() public view returns (uint256) {
        uint256 _price = price(feed1) * price(feed2);

        if (feedsTotalDecimals > targetDecimals) {
            _price = _price / (10 ** (feedsTotalDecimals - targetDecimals));
        } else if (targetDecimals > feedsTotalDecimals) {
            _price = _price * (10 ** (targetDecimals - feedsTotalDecimals));
        }

        return _price;
    }

    function price(address feed) public view returns (uint256) {
        (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
        require(answer >= 0, "amount should be positive");

        return uint256(answer);
    }
}