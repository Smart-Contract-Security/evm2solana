// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint160 observationIndex,
        uint160 observationCardinality,
        uint160 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface IuDOGEToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IuDOGEStaking {
    
    function recordJackpotFeeInToken(uint256 tokenAmount) external;
}

/**
 * @title uDOGEHook
 */
contract uDOGEHook is Ownable, ReentrancyGuard {


    IuDOGEToken public uDOGE;
    IuDOGEStaking public stakingContract;


    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public v3Pool;
    uint24 public constant POOL_FEE = 10000; // 1% fee pool
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;


    uint256 public constant MAX_ETH_CAP        = 1000 * 10**18;
    uint256 public constant MAX_MINT_PER_TX    = 1 * 10**18;
    uint256 public constant MAX_MINT_SUPPLY    = 99_000_000_000 * 10**18;
    uint256 public constant S                  = 21714724 * 10**10; // S = 217.14724 ETH
    uint256 public constant P0                 = 10**11;


    uint256 public constant MIN_GAS_RESERVE    = 50_000;


    uint256 public totalEthContributed;
    uint256 public totalEthReceived;
    uint256 public reservePool;
    uint256 public operationPool;
    uint256 public jackpotPool;


    uint256 public lpReserveBalance = 1_000_000_000 * 10**18;
    bool public isColdStartDone = false;


    mapping(address => uint256) public lastInteractionBlock;
    uint256 public constant COOLDOWN_BLOCKS = 100;

    event MintExecuted(address indexed user, uint256 ethSpent, uint256 tokenReceived);
    event BurnExecuted(address indexed user, uint256 tokenBurned, uint256 ethReturned, uint256 penaltyCharged);
    event LiquidityEngineTriggered(uint256 ethUsed, uint256 tokenUsed, string actionType);
    event SystemDegradedToPureBurn();
    event JackpotDistributed(uint256 ethUsed, uint256 uDogeAwarded);

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    
    function initialize(address _token, address _staking) external onlyOwner {
        require(address(uDOGE) == address(0), "Already initialized");
        uDOGE = IuDOGEToken(_token);
        stakingContract = IuDOGEStaking(_staking);
    }

    
    function setTestRouters(address _swapRouter, address _positionManager) external onlyOwner {
        if (_swapRouter != address(0)) swapRouter = ISwapRouter(_swapRouter);
        if (_positionManager != address(0)) positionManager = INonfungiblePositionManager(_positionManager);
    }

    
    function setV3Pool(address _v3Pool) external onlyOwner {
        v3Pool = _v3Pool;
    }

    
    function setLpReserveBalance(uint256 _newBalance) external onlyOwner {
        lpReserveBalance = _newBalance;
    }

    
    function setJackpotPool(uint256 _newPool) external onlyOwner {
        jackpotPool = _newPool;
    }

    
    function getMintPrice(uint256 ethAccumulated) public pure returns (uint256) {


        uint256 WAD = 10**18;


        uint256 x_wad = (ethAccumulated * WAD) / S;


        uint256 term1 = x_wad;


        uint256 term2 = (x_wad * x_wad) / WAD / 2;


        uint256 factor = WAD + term1 + term2;

        // P = P0 * factor / WAD
        return (P0 * factor) / WAD;
    }

    
    function mint() external payable nonReentrant {

        require(gasleft() >= MIN_GAS_RESERVE, "uDOGE: Insufficient gas");


        require(msg.value > 0, "uDOGE: Must send ETH");
        require(msg.value <= MAX_MINT_PER_TX, "uDOGE: Exceeds 1 ETH per-tx mint limit");

        require(totalEthReceived + msg.value <= MAX_ETH_CAP, "uDOGE: Exceeds 1000 ETH maximum mint cap");


        totalEthReceived += msg.value;


        uint256 fee    = msg.value / 100;
        uint256 netEth = msg.value - fee;
        jackpotPool += fee;


        uint256 price        = getMintPrice(totalEthContributed);
        uint256 tokensToMint = (netEth * 10**18) / price;


        totalEthContributed += netEth;
        uDOGE.mint(msg.sender, tokensToMint);


        uint256 halfNet = netEth / 2;
        reservePool   += halfNet;
        operationPool += netEth - halfNet;


        lastInteractionBlock[msg.sender] = block.number;

        emit MintExecuted(msg.sender, msg.value, tokensToMint);
    }

    
    function triggerLiquidityEngine() external nonReentrant {

        require(gasleft() >= 200_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for engine");
        require(operationPool >= 0.5 ether, "uDOGE: Operation pool must accumulate at least 0.5 ETH");


        operationPool -= 0.5 ether;


        if (!isColdStartDone) {
            _executeColdStart(0.5 ether);
        } else {
            _executeAdaptiveEngine(0.5 ether);
        }
    }

    
    function _executeColdStart(uint256 ethAmount) internal {

        uint256 tokenAmount = lpReserveBalance / 50;
        lpReserveBalance -= tokenAmount;


        if (v3Pool == address(0)) {

            address token0 = address(uDOGE) < WETH ? address(uDOGE) : WETH;
            address token1 = address(uDOGE) < WETH ? WETH : address(uDOGE);

            v3Pool = positionManager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, 7922816251426433759354);
        }


        uDOGE.approve(address(positionManager), tokenAmount);
        
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(uDOGE) < WETH ? address(uDOGE) : WETH,
            token1: address(uDOGE) < WETH ? WETH : address(uDOGE),
            fee: POOL_FEE,
            tickLower: -887200,
            tickUpper: 887200,
            amount0Desired: address(uDOGE) < WETH ? tokenAmount : ethAmount,
            amount1Desired: address(uDOGE) < WETH ? ethAmount : tokenAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(0x000000000000000000000000000000000000dEaD),
            deadline: block.timestamp + 300
        });

        positionManager.mint{value: ethAmount}(params);
        isColdStartDone = true;

        emit LiquidityEngineTriggered(ethAmount, tokenAmount, "COLD_START_BOOTSTRAP");
    }

    
    function _executeAdaptiveEngine(uint256 ethAmount) internal {

        uint256 p_v3   = getV3MarketPrice();
        uint256 p_floor = getFloorPrice();


        if (lpReserveBalance == 0) {

            _swapEthForTokensAndBurn(ethAmount);
            emit LiquidityEngineTriggered(ethAmount, 0, "PURE_BURN_DEGRADED");
            return;
        }


        uint256 ethBuy = ethAmount / 2;
        if (p_v3 < p_floor) {

            ethBuy = (ethAmount * 80) / 100; // 0.4 ETH
        }

        uint256 ethLP = ethAmount - ethBuy;


        _swapEthForTokensAndBurn(ethBuy);



        uint256 refPrice = p_v3 > 0 ? p_v3 : p_floor;

        if (refPrice == 0) {

            _swapEthForTokensAndBurn(ethLP);
            emit LiquidityEngineTriggered(ethAmount, 0, "ADAPTIVE_PUMP_AND_LP");
            return;
        }

        uint256 tokenLP = (ethLP * 10**18) / refPrice;
        if (tokenLP > lpReserveBalance) {
            tokenLP = lpReserveBalance;
        }

        lpReserveBalance -= tokenLP;

        uDOGE.approve(address(positionManager), tokenLP);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(uDOGE) < WETH ? address(uDOGE) : WETH,
            token1: address(uDOGE) < WETH ? WETH : address(uDOGE),
            fee: POOL_FEE,
            tickLower: -887200,
            tickUpper: 887200,
            amount0Desired: address(uDOGE) < WETH ? tokenLP : ethLP,
            amount1Desired: address(uDOGE) < WETH ? ethLP : tokenLP,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(0x000000000000000000000000000000000000dEaD),
            deadline: block.timestamp + 300
        });

        positionManager.mint{value: ethLP}(params);

        emit LiquidityEngineTriggered(ethAmount, tokenLP, "ADAPTIVE_PUMP_AND_LP");
    }

    
    function _swapEthForTokensAndBurn(uint256 ethAmount) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(uDOGE),
            fee: POOL_FEE,
            recipient: address(0x000000000000000000000000000000000000dEaD),
            deadline: block.timestamp + 300,
            amountIn: ethAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle{value: ethAmount}(params);
    }

    
    function burn(uint256 tokenAmount) external nonReentrant {

        require(gasleft() >= 60_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for burn");
        require(block.number >= lastInteractionBlock[msg.sender] + COOLDOWN_BLOCKS, "uDOGE: Cooldown lock active");
        require(tokenAmount > 0, "uDOGE: Must burn tokens");


        uint256 p_floor = getFloorPrice();
        uint256 p_v3    = getV3MarketPrice();


        require(p_floor > 0, "uDOGE: Floor price is zero, burn disabled");


        uint256 standardEthPayout = (tokenAmount * p_floor) / 10**18;
        
        uint256 totalAvailableReserve = reservePool;
        if (!isColdStartDone) {
            totalAvailableReserve = reservePool + operationPool;
        }
        require(totalAvailableReserve >= standardEthPayout, "uDOGE: Insufficient reserve liquidity");


        uint256 baseFee = standardEthPayout / 100;
        jackpotPool += baseFee;


        uint256 penaltyFee = 0;
        if (isColdStartDone && p_v3 < p_floor && p_floor > 0) {

            uint256 penaltyRate = 100 - ((p_v3 * 100) / p_floor) + 5;
            if (penaltyRate > 50) penaltyRate = 50;
            penaltyFee = (standardEthPayout * penaltyRate) / 100;
        }

        uint256 netPayout = standardEthPayout - baseFee - penaltyFee;


        uDOGE.burnFrom(msg.sender, tokenAmount);
        
        if (!isColdStartDone) {

            uint256 halfPayout = standardEthPayout / 2;
            reservePool -= halfPayout;
            operationPool -= (standardEthPayout - halfPayout);
        } else {
            reservePool -= standardEthPayout;
        }


        if (penaltyFee > 0) {
            uint256 halfPenalty = penaltyFee / 2;
            reservePool   += halfPenalty;
            operationPool += penaltyFee - halfPenalty;
        }


        lastInteractionBlock[msg.sender] = block.number;
        payable(msg.sender).transfer(netPayout);

        emit BurnExecuted(msg.sender, tokenAmount, netPayout, penaltyFee);
    }

    
    function distributeJackpot() external nonReentrant {

        require(gasleft() >= 150_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for jackpot");

        uint256 ethAmount = jackpotPool;
        require(ethAmount > 0, "uDOGE: No jackpot to distribute");


        jackpotPool = 0;


        uint256 p_v3 = getV3MarketPrice();
        uint256 minAmountOut = 0;
        if (p_v3 > 0) {
            uint256 expectedOut = (ethAmount * 10**18) / p_v3;
            minAmountOut = expectedOut / 2;
        }


        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn:           WETH,
            tokenOut:          address(uDOGE),
            fee:               POOL_FEE,
            recipient:         address(this),
            deadline:          block.timestamp + 600,
            amountIn:          ethAmount,
            amountOutMinimum:  minAmountOut,
            sqrtPriceLimitX96: 0
        });
        uint256 uDogeReceived = swapRouter.exactInputSingle{value: ethAmount}(params);

        require(uDogeReceived > 0, "uDOGE: Jackpot swap returned 0 tokens");


        uDOGE.approve(address(stakingContract), uDogeReceived);
        stakingContract.recordJackpotFeeInToken(uDogeReceived);

        emit JackpotDistributed(ethAmount, uDogeReceived);
    }

    
    function getFloorPrice() public view returns (uint256) {
        uint256 supply = IERC20(address(uDOGE)).totalSupply();
        uint256 circulating = supply > lpReserveBalance ? supply - lpReserveBalance : 0;

        if (circulating == 0) return P0;
        
        uint256 activeReserve = reservePool;
        if (!isColdStartDone) {
            activeReserve = reservePool + operationPool;
        }
        return (activeReserve * 10**18) / circulating;
    }

    
    function getV3MarketPrice() public view returns (uint256) {
        if (v3Pool == address(0)) return getFloorPrice();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(v3Pool).slot0();
        if (sqrtPriceX96 == 0) return getFloorPrice();


        if (address(uDOGE) < WETH) {
            // token0 = uDOGE, token1 = WETH
            // price = (sqrtPriceX96^2 * 10^18) / 2^192
            return (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 10**18) >> (96 * 2);
        } else {
            // token0 = WETH, token1 = uDOGE
            // price = 1 / (sqrtPriceX96^2 / 2^192) = (2^192 * 10^18) / sqrtPriceX96^2
            return (10**18 << (96 * 2)) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        }
    }


    receive() external payable {}
}
