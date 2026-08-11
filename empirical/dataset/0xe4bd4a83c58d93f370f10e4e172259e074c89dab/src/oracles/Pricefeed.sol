// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

interface IFeed {
    function getPrice() external view returns (uint256); // returns USD price in 1e18;
}

contract PriceFeed is Ownable {
    mapping(address => address) public pricefeeds;

    constructor() Ownable(msg.sender) {}

    function setPricefeed(address asset, address feed) external onlyOwner {
        pricefeeds[asset] = feed;
    }

    function hasPriceFeed(address asset) public view returns (bool) {
        return (pricefeeds[asset] != address(0));
    }

    function getPrice(address asset) public view returns (uint256 price) {
        address feed = pricefeeds[asset];
        require(feed != address(0), "feed not set");

        price = IFeed(feed).getPrice();
        require(price != 0, "price cant be 0");

        return price;
    }
}
