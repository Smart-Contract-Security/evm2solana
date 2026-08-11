// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./PriceOracle.sol";
import "../MErc20.sol";
import "../EIP20Interface.sol";
import "./AggregatorV3Interface.sol";

contract ChainlinkOracle is PriceOracle {
    address public admin;
    bytes32 public nativeToken;

    mapping(address => uint256) internal prices;
    mapping(bytes32 => address) internal feeds;

    event PricePosted(
        address asset,
        uint256 previousPriceMantissa,
        uint256 requestedPriceMantissa,
        uint256 newPriceMantissa
    );
    event NewAdmin(address oldAdmin, address newAdmin);
    event FeedSet(address feed, string symbol);

    constructor(string memory _nativeToken) {
        admin = tx.accounts[0].key;
        nativeToken = keccak256(abi.encodePacked(_nativeToken));
    }

    modifier onlyAdmin() {
        require(tx.accounts[0].key == admin, "only admin may call");
        _;
    }

    function getUnderlyingPrice(
        address mToken
    ) public view override returns (uint256) {
        string memory symbol = MErc20(mToken).symbol();
        if (keccak256(abi.encodePacked(symbol)) == nativeToken) {
            return getChainlinkPrice(getFeed(symbol));
        } else {
            return getPrice(mToken);
        }
    }

    function getPrice(address mToken) internal view returns (uint256 price) {
        EIP20Interface token = EIP20Interface(
            MErc20(mToken).underlying()
        );

        if (prices[address(token)] != 0) {
            price = prices[address(token)];
        } else {
            price = getChainlinkPrice(getFeed(token.symbol()));
        }

        uint256 decimalDelta = uint256(18) - uint256(token.decimals());
        if (decimalDelta > 0) {
            return price * (10 ** decimalDelta);
        } else {
            return price;
        }
    }

    function getChainlinkPrice(
        address feed
    ) internal view returns (uint256) {
        AggregatorV3Interface feedContract = AggregatorV3Interface(feed);
        (, int256 answer, , uint256 updatedAt, ) = feedContract.latestRoundData();
        require(answer > 0, "Chainlink price cannot be lower than 0");
        require(updatedAt != 0, "Round is in incompleted state");

        uint256 decimalDelta = uint256(18) - feedContract.decimals();
        if (decimalDelta > 0) {
            return uint256(answer) * (10 ** decimalDelta);
        } else {
            return uint256(answer);
        }
    }

    function setUnderlyingPrice(
        address mToken,
        uint256 underlyingPriceMantissa
    ) external onlyAdmin {
        address asset = address(MErc20(mToken).underlying());
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint256 price) external onlyAdmin {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    function setFeed(string calldata symbol, address feed) external onlyAdmin {
        require(
            feed != address(0) && feed != address(this),
            "invalid feed address"
        );
        emit FeedSet(feed, symbol);
        feeds[keccak256(abi.encodePacked(symbol))] = feed;
    }

    function getFeed(
        string memory symbol
    ) public view returns (address) {
        return feeds[keccak256(abi.encodePacked(symbol))];
    }

    function assetPrices(address asset) external view returns (uint256) {
        return prices[asset];
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        address oldAdmin = admin;
        admin = newAdmin;
        emit NewAdmin(oldAdmin, newAdmin);
    }
}