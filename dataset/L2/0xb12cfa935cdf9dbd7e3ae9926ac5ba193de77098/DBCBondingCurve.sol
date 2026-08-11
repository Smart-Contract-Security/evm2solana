// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

interface IUniswapV4PositionManager {
    function mint(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        address recipient
    ) external returns (uint256 tokenId);
}

contract DBCCurve is ReentrancyGuard {
    IERC20 public tokenAddress;
    address public devAddress;
    
    uint256 public constant FUNDING_CAP = 2.5 ether;
    uint256 public constant BUY_FEE_PERCENT = 1;  
    uint256 public constant SELL_FEE_PERCENT = 4; 
    
    uint256 public constant MAX_CURVE_TOKENS = 200_000_000 * 10**18; 
    uint256 public constant VIRTUAL_ETH_RESERVE = 1 ether; 
    uint256 public constant VIRTUAL_TOKEN_RESERVE = 1_000_000_000 * 10**18;
    
    uint256 public tokenReserve;
    uint256 public totalEthCollected;
    bool public isMigrated;
    bool public isInitialized;

    event CurveInitialized();
    event TokensBought(address indexed buyer, uint256 ethSpent, uint256 tokensReceived);
    event TokensSold(address indexed seller, uint256 tokensSpent, uint256 ethReceived);
    event MigratedToUniswapV4(uint256 ethAmount, uint256 tokenAmount);

    constructor(address _devAddress) {
        devAddress = _devAddress;
        isMigrated = false;
        isInitialized = false;
    }

    function initializeCurve(address _tokenAddress) external {
        require(msg.sender == devAddress, "Not dev");
        require(!isInitialized, "Initialized");
        
        tokenAddress = IERC20(_tokenAddress);
        require(tokenAddress.balanceOf(address(this)) >= MAX_CURVE_TOKENS, "Need 200M DBC");
        
        tokenReserve = MAX_CURVE_TOKENS;
        isInitialized = true;
        emit CurveInitialized();
    }

    function getEthToBuyTokens(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount < tokenReserve, "Insufficient tokens");
        
        uint256 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint256 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint256 baseEthCost = (currentEthReserve * tokenAmount) / (currentTokenReserve - tokenAmount);
        uint256 fee = (baseEthCost * BUY_FEE_PERCENT) / 100;
        
        return baseEthCost + fee;
    }

    function getEthFromSellTokens(uint256 tokenAmount) public view returns (uint256) {
        uint256 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint256 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint256 baseEthOut = (currentEthReserve * tokenAmount) / (currentTokenReserve + tokenAmount);
        uint256 fee = (baseEthOut * SELL_FEE_PERCENT) / 100;
        
        return baseEthOut - fee;
    }

    function getTokensOutForEth(uint256 ethAmount) public view returns (uint256) {
        uint256 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint256 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        return (currentTokenReserve * ethAmount) / (currentEthReserve + ethAmount);
    }

    function buy() external payable nonReentrant {
        require(isInitialized, "Not active");
        require(!isMigrated, "Migrated");
        require(msg.value > 0, "Zero ETH");

        uint256 fee = (msg.value * BUY_FEE_PERCENT) / 100;
        uint256 netEth = msg.value - fee;

        uint256 ethToCurve = netEth;
        uint256 refundEth = 0;

        if (totalEthCollected + netEth > FUNDING_CAP) {
            ethToCurve = FUNDING_CAP - totalEthCollected;
            refundEth = netEth - ethToCurve;
        }

        uint256 tokensToBuyer = getTokensOutForEth(ethToCurve);
        require(tokensToBuyer > 0 && tokensToBuyer <= tokenReserve, "Invalid amount");
        
        totalEthCollected += ethToCurve;
        tokenReserve -= tokensToBuyer;

        tokenAddress.transfer(msg.sender, tokensToBuyer);

        (bool successFee, ) = devAddress.call{value: fee}("");
        require(successFee, "Fee transfer failed");

        if (refundEth > 0) {
            (bool successRefund, ) = msg.sender.call{value: refundEth}("");
            require(successRefund, "Refund failed");
        }

        emit TokensBought(msg.sender, ethToCurve, tokensToBuyer);

        if (totalEthCollected >= FUNDING_CAP) {
            _migrateToUniswapV4();
        }
    }

    function sell(uint256 tokenAmount) external nonReentrant {
        require(isInitialized, "Not active");
        require(!isMigrated, "Migrated");
        require(tokenAmount > 0, "Zero amount");

        uint256 currentEthReserve = VIRTUAL_ETH_RESERVE + totalEthCollected;
        uint256 currentTokenReserve = VIRTUAL_TOKEN_RESERVE - (MAX_CURVE_TOKENS - tokenReserve);
        
        uint256 ethOut = (currentEthReserve * tokenAmount) / (currentTokenReserve + tokenAmount);
        
        uint256 fee = (ethOut * SELL_FEE_PERCENT) / 100;
        uint256 netEth = ethOut - fee;

       
        totalEthCollected -= ethOut;
        tokenReserve += tokenAmount;

        tokenAddress.transferFrom(msg.sender, address(this), tokenAmount);

       
        (bool successNet, ) = msg.sender.call{value: netEth}("");
        require(successNet, "ETH transfer failed");

        (bool successFee, ) = devAddress.call{value: fee}("");
        require(successFee, "Fee transfer failed");

        emit TokensSold(msg.sender, tokenAmount, netEth);
    }

    function _migrateToUniswapV4() internal {
        isMigrated = true;

        uint256 ethForLP = address(this).balance; 
        uint256 tokenForLP = tokenAddress.balanceOf(address(this));

        emit MigratedToUniswapV4(ethForLP, tokenForLP);
    }
}