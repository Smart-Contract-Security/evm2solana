// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// these contracts will be deployed on ethereum and binance smart chain to collect fees and the process will happen on polygon network

import "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Collector
 * @dev A contract that allows users to buy tokens by sending ether. The rate is set in dollars and fetched using Chainlink's data feed.
 */
contract collector is Ownable {
    uint private _rateInDollars = 2 * 1e8; // 2 Dollars
    AggregatorV3Interface internal dataFeed;

    /**
     * @dev Emitted when tokens are bought.
     * @param buyer The address of the buyer.
     * @param ethValue The amount of ether sent.
     * @param amount The amount of tokens bought.
     */
    event TokensBought(address buyer, uint ethValue, uint256 amount);

    /**
     * @dev Emitted when the token rate is changed.
     * @param owner The address of the owner.
     * @param rate The new rate in dollars.
     */
    event RateChanged(address owner, uint rate);

    /**
     * @dev Initialise the Chainlink Data Feed Address.
     * @param owner The address of the contract owner.
     */
    constructor(address owner) Ownable(owner) {
        dataFeed = AggregatorV3Interface(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        );

        // 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE bnb 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 eth
        // 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526 bnb testnet 0x694AA1769357215DE4FAC081bf1f309aDC325306 sepolia
    }

    receive() external payable {
        // collect fees
    }

    /**
     * @notice Buy tokens by sending ether.
     * @dev Do not use this function directly to send ether as it will lock the sent ether. Please use our platform to buy tokens.
     * @param _amount The amount of tokens to buy.
     */
    function buyTokens(uint256 _amount) external payable {
        require(
            _amount > 0,
            "Collector: amount of tokens must be greater than 0"
        );

        require(
            msg.value > 0,
            "Collector: amount of ether sent must be greater than 0"
        );

        uint256 dollarsValue = _amount * getRate();
        uint ethValue = (dollarsValue /
            uint(getChainlinkDataFeedLatestAnswer()));

        require(
            msg.value >= ethValue,
            "Collector: amount of ether sent must be equal to the amount of ether required"
        );

        // collect fees
        emit TokensBought(msg.sender, msg.value, _amount);
    }

    /**
     * @notice Withdraw all collected ether to the owner's address.
     */
    function withdrawFunds() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @notice Set a new Chainlink data feed address.
     * @param _dataFeed The address of the new data feed.
     */
    function setDataFeed(address _dataFeed) external onlyOwner {
        dataFeed = AggregatorV3Interface(_dataFeed);
    }

    /**
     * @notice Change the rate in dollars. Rate should be in 1e8 for ex. 2 dollars is (2 * 1e8)
     * @param _rate The new rate in dollars.
     */
    function changeRate(uint _rate) external onlyOwner {
        _rateInDollars = _rate;
        emit RateChanged(owner(), _rate);
    }

    /**
     * @notice Get the current Chainlink data feed address.
     * @return _dataFeed address of the data feed.
     */
    function getDataFeedAddress() external view returns (address _dataFeed) {
        _dataFeed = address(dataFeed);
    }

    /**
     * @notice Get the current rate in dollars.
     * @return _rate current rate in dollars.
     */
    function getRate() public view returns (uint256 _rate) {
        _rate = _rateInDollars;
    }

    /**
     * @notice Get the latest answer from the Chainlink data feed.
     * @return answer latest answer from the data feed.
     */
    function getChainlinkDataFeedLatestAnswer()
        public
        view
        returns (int answer)
    {
        // prettier-ignore
        (
            /* uint80 roundID */,
            answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
    }
}
