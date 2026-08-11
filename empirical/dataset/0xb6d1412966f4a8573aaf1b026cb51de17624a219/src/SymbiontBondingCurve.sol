// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ISymbiontNFT.sol";

/**
 * @title SymbiontBondingCurve
 * @notice Constant product bonding curve with virtual reserves (x * y = k)
 *
 * Constructor params allow different scales:
 * - Mainnet: virtualEth=3, virtualToken=10730, graduationVirtualEth=13, totalSupply=10000
 * - Testnet 1:10: virtualEth=0.3, virtualToken=10730, graduationVirtualEth=1.3
 *
 * Buy: fee from ethIn, then virtualEth += effectiveEth, virtualToken = K / virtualEth
 * Sell: virtualToken += tokensIn, virtualEth = K / virtualToken, then fee from ethOut
 */
contract SymbiontBondingCurve is Ownable, ReentrancyGuard {
    // Token
    IERC20 public immutable token;

    // Symbiont NFT
    ISymbiontNFT public symbiontNFT;

    // Scale-independent constants
    uint256 public constant TOTAL_SUPPLY = 10_000 * 1e18;
    uint256 public constant TRADING_FEE_BPS = 100; // 1%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant DEV_FEE_BPS = 2500; // 25% on graduation

    // Scale-dependent (immutable — set at deploy time)
    uint256 public immutable INITIAL_VIRTUAL_ETH;
    uint256 public immutable INITIAL_VIRTUAL_TOKEN;
    uint256 public immutable K;
    uint256 public immutable GRADUATION_VIRTUAL_ETH;
    
    // State - Virtual Reserves (change with each trade)
    uint256 public virtualEth;
    uint256 public virtualToken;
    
    // State - Real tracking
    uint256 public realETHCollected; // Total ETH collected (after fees)
    uint256 public tokensSold;
    bool public graduated;
    
    address public treasury;
    address public hook; // SymbiontHook (replaces liquidityManager)
    address public rewardPool;
    
    // Events
    event Buy(address indexed buyer, uint256 ethIn, uint256 tokensOut, uint256 newPrice);
    event Sell(address indexed seller, uint256 tokensIn, uint256 ethOut, uint256 newPrice);
    event Graduated(uint256 ethToLP, uint256 tokensToLP, uint256 tokensToRewards);
    event SymbiontNFTSet(address indexed nft);
    
    constructor(
        address _token,
        address _treasury,
        address _hook,
        address _rewardPool,
        uint256 _virtualEth,
        uint256 _virtualToken,
        uint256 _graduationVirtualEth
    ) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token");
        require(_treasury != address(0), "Invalid treasury");
        require(_hook != address(0), "Invalid hook");
        require(_rewardPool != address(0), "Invalid reward pool");
        require(_virtualEth > 0 && _virtualToken > 0, "Invalid virtuals");
        require(_graduationVirtualEth > _virtualEth, "Graduation > initial");

        token = IERC20(_token);
        treasury = _treasury;
        hook = _hook;
        rewardPool = _rewardPool;

        INITIAL_VIRTUAL_ETH = _virtualEth;
        INITIAL_VIRTUAL_TOKEN = _virtualToken;
        K = _virtualEth * _virtualToken;
        GRADUATION_VIRTUAL_ETH = _graduationVirtualEth;

        // Initialize virtual reserves
        virtualEth = _virtualEth;
        virtualToken = _virtualToken;
    }
    
    function setRewardPool(address _rewardPool) external onlyOwner {
        require(_rewardPool != address(0), "Invalid reward pool");
        rewardPool = _rewardPool;
    }
    
    function setSymbiontNFT(address _symbiontNFT) external onlyOwner {
        require(_symbiontNFT != address(0), "Invalid NFT");
        symbiontNFT = ISymbiontNFT(_symbiontNFT);
        emit SymbiontNFTSet(_symbiontNFT);
    }
    
    function setHook(address _hook) external onlyOwner {
        require(_hook != address(0), "Invalid hook");
        hook = _hook;
    }
    
    function getCurrentPrice() public view returns (uint256) {
        if (virtualToken == 0) return 0;
        return (virtualEth * 1e18) / virtualToken;
    }
    
    /**
     * @notice Get the final price at graduation (when virtualEth reaches GRADUATION_VIRTUAL_ETH)
     * @return price Final price in ETH per token (18 decimals)
     */
    function getGraduationPrice() public view returns (uint256) {
        // At graduation: virtualEth = GRADUATION_VIRTUAL_ETH
        // virtualToken = K / GRADUATION_VIRTUAL_ETH
        // price = virtualEth / virtualToken = GRADUATION_VIRTUAL_ETH / (K / GRADUATION_VIRTUAL_ETH)
        // price = (GRADUATION_VIRTUAL_ETH * GRADUATION_VIRTUAL_ETH) / K
        return (GRADUATION_VIRTUAL_ETH * GRADUATION_VIRTUAL_ETH * 1e18) / K;
    }
    
    function calculateBuy(uint256 ethIn) public view returns (uint256 tokensOut) {
        require(!graduated, "Already graduated");
        require(ethIn > 0, "Zero ETH");
        
        uint256 fee = (ethIn * TRADING_FEE_BPS) / BPS_DENOMINATOR;
        uint256 effectiveEth = ethIn - fee;
        
        uint256 newVirtualEth = virtualEth + effectiveEth;
        uint256 newVirtualToken = K / newVirtualEth;
        
        tokensOut = virtualToken - newVirtualToken;
        require(tokensOut <= TOTAL_SUPPLY - tokensSold, "Exceeds available");
    }
    
    function calculateSell(uint256 tokensIn) public view returns (uint256 ethOut) {
        require(!graduated, "Already graduated");
        require(tokensIn > 0, "Zero tokens");
        require(tokensIn <= tokensSold, "Exceeds sold");
        
        uint256 newVirtualToken = virtualToken + tokensIn;
        uint256 newVirtualEth = K / newVirtualToken;
        
        uint256 effectiveEth = virtualEth - newVirtualEth;
        uint256 fee = (effectiveEth * TRADING_FEE_BPS) / BPS_DENOMINATOR;
        ethOut = effectiveEth - fee;
        
        require(ethOut <= realETHCollected, "Insufficient real ETH");
    }
    
    function buy() external payable nonReentrant {
        require(!graduated, "Already graduated");
        require(msg.value > 0, "Zero ETH");
        
        // Calculate max ETH that can be accepted before graduation
        uint256 maxEth = msg.value;
        uint256 refund = 0;
        
        if (virtualEth + (msg.value * (BPS_DENOMINATOR - TRADING_FEE_BPS) / BPS_DENOMINATOR) > GRADUATION_VIRTUAL_ETH) {
            // Calculate exact ETH needed to reach graduation cap
            uint256 ethNeeded = GRADUATION_VIRTUAL_ETH - virtualEth;
            // Add back the fee to get total ETH input needed
            maxEth = (ethNeeded * BPS_DENOMINATOR) / (BPS_DENOMINATOR - TRADING_FEE_BPS);
            refund = msg.value - maxEth;
        }
        
        uint256 fee = (maxEth * TRADING_FEE_BPS) / BPS_DENOMINATOR;
        uint256 effectiveEth = maxEth - fee;
        
        uint256 tokensOut = calculateBuy(maxEth);
        require(tokensOut > 0, "Zero tokens out");
        
        // Update virtual reserves
        uint256 newVirtualEth = virtualEth + effectiveEth;
        uint256 newVirtualToken = K / newVirtualEth;
        
        virtualEth = newVirtualEth;
        virtualToken = newVirtualToken;
        
        // Update real tracking
        realETHCollected += effectiveEth;
        tokensSold += tokensOut;
        
        // Send fee to treasury
        (bool feeSuccess, ) = treasury.call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");
        
        require(token.transfer(msg.sender, tokensOut), "Transfer failed");
        
        // Refund excess ETH if any
        if (refund > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit Buy(msg.sender, maxEth, tokensOut, getCurrentPrice());
        
        // Auto-mint NFT if user doesn't have one
        if (address(symbiontNFT) != address(0)) {
            if (symbiontNFT.walletToTokenId(msg.sender) == 0) {
                // Will revert if user doesn't have enough SYMB, but that's OK
                // since they just bought tokens
                try symbiontNFT.autoMint(msg.sender) {} catch {}
            }
        }
        
        // Check graduation (when virtualETH >= 0.013)
        if (virtualEth >= GRADUATION_VIRTUAL_ETH) {
            _graduate();
        }
    }
    
    function sell(uint256 tokensIn) external nonReentrant {
        require(!graduated, "Already graduated");
        require(tokensIn > 0, "Zero tokens");
        
        uint256 ethOut = calculateSell(tokensIn);
        require(ethOut > 0, "Zero ETH out");
        
        // Update virtual reserves
        uint256 newVirtualToken = virtualToken + tokensIn;
        uint256 newVirtualEth = K / newVirtualToken;
        
        uint256 effectiveEth = virtualEth - newVirtualEth;
        uint256 fee = (effectiveEth * TRADING_FEE_BPS) / BPS_DENOMINATOR;
        
        virtualToken = newVirtualToken;
        virtualEth = newVirtualEth;
        
        // Update real tracking
        realETHCollected -= effectiveEth;
        tokensSold -= tokensIn;
        
        require(token.transferFrom(msg.sender, address(this), tokensIn), "Transfer failed");
        
        // Send fee to treasury
        (bool feeSuccess, ) = treasury.call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");
        
        (bool success, ) = msg.sender.call{value: ethOut}("");
        require(success, "ETH transfer failed");
        
        // Health penalty now handled by token._update() → notifySell()
        // No need to call applyDecay here anymore
        
        emit Sell(msg.sender, tokensIn, ethOut, getCurrentPrice());
    }
    
    function _graduate() internal {
        require(!graduated, "Already graduated");
        
        graduated = true;
        
        uint256 devFee = (realETHCollected * DEV_FEE_BPS) / BPS_DENOMINATOR;
        uint256 lpETH = realETHCollected - devFee;
        
        uint256 remainingTokens = TOTAL_SUPPLY - tokensSold;
        uint256 graduationPrice = getCurrentPrice();
        
        // Calculate tokens needed for LP
        uint256 lpTokens = (lpETH * 1e18) / graduationPrice;
        uint256 rewardTokens = remainingTokens - lpTokens;
        
        // Send dev fee to treasury
        (bool success, ) = treasury.call{value: devFee}("");
        require(success, "Dev fee transfer failed");
        
        // Transfer reward tokens to RewardPool
        if (rewardTokens > 0) {
            require(token.transfer(rewardPool, rewardTokens), "Reward transfer failed");
        }
        
        // Transfer LP tokens and ETH to Hook for auto-migration
        if (hook != address(0)) {
            require(token.transfer(hook, lpTokens), "LP token transfer failed");
            
            // Call receiveLiquidity() to register ETH + tokens
            (bool hookSuccess, ) = hook.call{value: lpETH}(abi.encodeWithSignature("receiveLiquidity()"));
            require(hookSuccess, "Receive liquidity failed");
        }
        
        emit Graduated(lpETH, lpTokens, rewardTokens);
    }
    
    receive() external payable {
        revert("Use buy() function");
    }
}
