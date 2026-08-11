// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Uniswap V3 交互标准接口
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
    /**
     * @dev Hook 调用：以 uDOGE 代币形式派发抽奖奖金。
     *      Hook 应预先 approve 此合约所需额度后再调用。
     */
    function recordJackpotFeeInToken(uint256 tokenAmount) external;
}

/**
 * @title uDOGEHook
 * @dev uDOGE 的大主控 Hook 合约。
 * 承载了 1000 ETH 联合曲线 Mint、V3 自适应拉升 LP 引擎、自适应降级 100% 纯 ETH 销毁、
 * 方案 B 偏离度自适应退出税以及外部 Keeper 触发逻辑。
 */
contract uDOGEHook is Ownable, ReentrancyGuard {

    // 核心代币与质押合约
    IuDOGEToken public uDOGE;
    IuDOGEStaking public stakingContract;

    // Uniswap V3 相关路由与池子配置
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public v3Pool;
    uint24 public constant POOL_FEE = 10000; // 1% fee pool
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // 联合曲线数学参数
    uint256 public constant MAX_ETH_CAP        = 1000 * 10**18; // 总募资上限：1,000 ETH
    uint256 public constant MAX_MINT_PER_TX    = 1 * 10**18;   // 单笔 Mint 上限：1 ETH
    uint256 public constant MAX_MINT_SUPPLY    = 99_000_000_000 * 10**18; // 990 亿枚 Mint 配额
    uint256 public constant S                  = 21714724 * 10**10; // S = 217.14724 ETH
    uint256 public constant P0                 = 10**11; // 初始基准价格调节因子

    // Gas 预留阈值（低于此值拒绝执行高 Gas 操作，防止 OOG 导致状态不一致）
    uint256 public constant MIN_GAS_RESERVE    = 50_000; // 每个关键操作前必须保留 5 万 Gas

    // ETH 池余额跟踪
    uint256 public totalEthContributed; // 累计净 ETH（扣除手续费后），用于联合曲线定价
    uint256 public totalEthReceived;    // 累计毛 ETH（用户实际打入金额），用于 1000 ETH 上限检查
    uint256 public reservePool;         // 保底准备金库 ETH 余额 (50% 的净 Mint 资金)
    uint256 public operationPool;       // 运作池 ETH 余额 (50% 的净 Mint 资金，用于 LP 拉升)
    uint256 public jackpotPool;         // 累计累积的 1% 手续费抽奖池（以 ETH 计量存储）

    // 10 亿预留 LP 代币储备状态
    uint256 public lpReserveBalance = 1_000_000_000 * 10**18; // 10 亿枚储备
    bool public isColdStartDone = false; // 是否已经完成了第一个 1 ETH 的蓄水冷启动

    // 区块冷却锁防止闪电贷
    mapping(address => uint256) public lastInteractionBlock;
    uint256 public constant COOLDOWN_BLOCKS = 100; // 100个区块冷却 (约 20 分钟)

    event MintExecuted(address indexed user, uint256 ethSpent, uint256 tokenReceived);
    event BurnExecuted(address indexed user, uint256 tokenBurned, uint256 ethReturned, uint256 penaltyCharged);
    event LiquidityEngineTriggered(uint256 ethUsed, uint256 tokenUsed, string actionType);
    event SystemDegradedToPureBurn();
    event JackpotDistributed(uint256 ethUsed, uint256 uDogeAwarded);

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /**
     * @dev 初始化代币与质押合约（并支持测试环境注入 Mock 路由）
     */
    function initialize(address _token, address _staking) external onlyOwner {
        require(address(uDOGE) == address(0), "Already initialized");
        uDOGE = IuDOGEToken(_token);
        stakingContract = IuDOGEStaking(_staking);
    }

    /**
     * @dev 注入测试路由 (仅用于本地沙盒 Mock 测试，链上所有者可控)
     */
    function setTestRouters(address _swapRouter, address _positionManager) external onlyOwner {
        if (_swapRouter != address(0)) swapRouter = ISwapRouter(_swapRouter);
        if (_positionManager != address(0)) positionManager = INonfungiblePositionManager(_positionManager);
    }

    /**
     * @dev 设定 V3 池子地址 (仅限管理权设置)
     */
    function setV3Pool(address _v3Pool) external onlyOwner {
        v3Pool = _v3Pool;
    }

    /**
     * @dev 人工调节流动性代币储备余额 (供测试及极端事件调节)
     */
    function setLpReserveBalance(uint256 _newBalance) external onlyOwner {
        lpReserveBalance = _newBalance;
    }

    /**
     * @dev 人工调节 Jackpot 大奖池余额
     */
    function setJackpotPool(uint256 _newPool) external onlyOwner {
        jackpotPool = _newPool;
    }

    /**
     * @dev 联合曲线价格计算公式：根据累计 ETH 额度，计算当前的 Mint 单价
     */
    function getMintPrice(uint256 ethAccumulated) public pure returns (uint256) {
        // P_mint = P0 * (1 + x + x²/2)，其中 x = ethAccumulated/S
        // 使用 WAD (1e18) 定点数分级计算，避免中间值溢出
        uint256 WAD = 10**18;

        // x = ethAccumulated * WAD / S，单位 WAD（即 x 已放大 1e18 倍）
        uint256 x_wad = (ethAccumulated * WAD) / S;

        // 一次项贡献（单位 WAD）：x_wad
        uint256 term1 = x_wad;

        // 二次项贡献（单位 WAD）：x² / 2
        uint256 term2 = (x_wad * x_wad) / WAD / 2;

        // factor = WAD + term1 + term2，转换为与 WAD 同量纲的系数
        uint256 factor = WAD + term1 + term2;

        // P = P0 * factor / WAD
        return (P0 * factor) / WAD;
    }

    /**
     * @dev 1000 ETH 联合曲线 Mint 主入口
     * 限制：单笔最多 1 ETH，累计总量不超过 1000 ETH 上限。
     */
    function mint() external payable nonReentrant {
        // --- Gas 预留检查 ---
        require(gasleft() >= MIN_GAS_RESERVE, "uDOGE: Insufficient gas");

        // --- 输入校验 ---
        require(msg.value > 0, "uDOGE: Must send ETH");
        require(msg.value <= MAX_MINT_PER_TX, "uDOGE: Exceeds 1 ETH per-tx mint limit");
        // 使用 totalEthReceived（毛 ETH）与 MAX_ETH_CAP 对比，保证单位一致
        require(totalEthReceived + msg.value <= MAX_ETH_CAP, "uDOGE: Exceeds 1000 ETH maximum mint cap");

        // 0. 更新毛 ETH 总量（先记录，防止重入）
        totalEthReceived += msg.value;

        // 1. 计算 1% 手续费并扣除
        uint256 fee    = msg.value / 100;
        uint256 netEth = msg.value - fee;
        jackpotPool += fee;

        // 2. 根据联合曲线计算该笔净 ETH 可铸造的代币数
        uint256 price        = getMintPrice(totalEthContributed);
        uint256 tokensToMint = (netEth * 10**18) / price;

        // 3. 更新净 ETH 账本并铸造给用户
        totalEthContributed += netEth;
        uDOGE.mint(msg.sender, tokensToMint);

        // 4. 分流净 ETH：50% 保底准备金库 + 50% 运作池
        uint256 halfNet = netEth / 2;
        reservePool   += halfNet;
        operationPool += netEth - halfNet; // 消除 Solidity 整除取余误差

        // 5. 设置冷却锁，防止闪电贷在同区块 Burn
        lastInteractionBlock[msg.sender] = block.number;

        emit MintExecuted(msg.sender, msg.value, tokensToMint);
    }

    /**
     * @dev 外部 Keeper 触发流动性拉升与 LP 追加引擎
     * 任何账户均可调用，鼓励社区志愿 Keeper 机器人自动触发。
     */
    function triggerLiquidityEngine() external nonReentrant {
        // --- Gas 预留检查：Swap + LP + 事件至少需要 20 万 Gas ---
        require(gasleft() >= 200_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for engine");
        require(operationPool >= 0.5 ether, "uDOGE: Operation pool must accumulate at least 0.5 ETH");

        // 每次触发提取 0.5 ETH 额度进行处理 (对应用户约 1 ETH 的 gross mint 总额)
        operationPool -= 0.5 ether;

        // 检查是否已经完成了第一次的 0.5 ETH 蓄水冷启动
        if (!isColdStartDone) {
            _executeColdStart(0.5 ether);
        } else {
            _executeAdaptiveEngine(0.5 ether);
        }
    }

    /**
     * @dev 阶段 A：第一个 1 ETH 的蓄水冷启动
     */
    function _executeColdStart(uint256 ethAmount) internal {
        // 按保底单价折算需要配合的储备代币数量
        uint256 tokenAmount = lpReserveBalance / 50; // 冷启动注入 2% 的储备代币 (约 2000 万枚)
        lpReserveBalance -= tokenAmount;

        // 1. 初始化 V3 池子 (如果尚未建立)
        if (v3Pool == address(0)) {
            // WETH 和 uDOGE 排列顺序决定 token0/token1
            address token0 = address(uDOGE) < WETH ? address(uDOGE) : WETH;
            address token1 = address(uDOGE) < WETH ? WETH : address(uDOGE);
            // 设定初始部署的 sqrtPriceX96 (这里以 1 uDOGE = 0.000000025 ETH 举例折算)
            v3Pool = positionManager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, 7922816251426433759354);
        }

        // 2. 授权给 positionManager 并打入双边 LP
        uDOGE.approve(address(positionManager), tokenAmount);
        
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(uDOGE) < WETH ? address(uDOGE) : WETH,
            token1: address(uDOGE) < WETH ? WETH : address(uDOGE),
            fee: POOL_FEE,
            tickLower: -887200,
            tickUpper: 887200, // 全区间 Full Range
            amount0Desired: address(uDOGE) < WETH ? tokenAmount : ethAmount,
            amount1Desired: address(uDOGE) < WETH ? ethAmount : tokenAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(0x000000000000000000000000000000000000dEaD), // 永久烧毁 LP NFT 到黑洞
            deadline: block.timestamp + 300
        });

        positionManager.mint{value: ethAmount}(params);
        isColdStartDone = true;

        emit LiquidityEngineTriggered(ethAmount, tokenAmount, "COLD_START_BOOTSTRAP");
    }

    /**
     * @dev 阶段 B：后续常规自适应拉升 LP 引擎 (包含方案 A 降级逻辑)
     */
    function _executeAdaptiveEngine(uint256 ethAmount) internal {
        // 实时读取 V3 的市场价与保底价
        uint256 p_v3   = getV3MarketPrice();
        uint256 p_floor = getFloorPrice();

        // 1. 判断是否进入方案 A 狂暴降级模式：储备代币彻底为 0
        if (lpReserveBalance == 0) {
            // 100% 资金（全部 0.5 ETH）直接买入销毁！
            _swapEthForTokensAndBurn(ethAmount);
            emit LiquidityEngineTriggered(ethAmount, 0, "PURE_BURN_DEGRADED");
            return;
        }

        // 2. 正常自适应比例计算
        uint256 ethBuy = ethAmount / 2; // 常规下 0.25 ETH 买入销毁
        if (p_v3 < p_floor) {
            // 市场价被砸穿保底，启动强力拉升，分配 80% 资金去买入销毁
            ethBuy = (ethAmount * 80) / 100; // 0.4 ETH
        }

        uint256 ethLP = ethAmount - ethBuy;

        // 3. 执行买入并销毁 (Pump & Burn)
        _swapEthForTokensAndBurn(ethBuy);

        // 4. 执行追加 LP 焊死 (Defense)
        // 安全获取市场价：若 V3 价格为 0（池子尚未创建或数据异常），则寄存至保底价防止除零
        uint256 refPrice = p_v3 > 0 ? p_v3 : p_floor;
        // 如果 refPrice 仍为 0（表示储备金和流通量均为 0），则跳过 LP 添加
        if (refPrice == 0) {
            // 极端情况：无法定价，将剩余 ETH 也用于买入销毁
            _swapEthForTokensAndBurn(ethLP);
            emit LiquidityEngineTriggered(ethAmount, 0, "ADAPTIVE_PUMP_AND_LP");
            return;
        }

        uint256 tokenLP = (ethLP * 10**18) / refPrice;
        if (tokenLP > lpReserveBalance) {
            tokenLP = lpReserveBalance; // 限制不能超出剩余储备
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
            recipient: address(0x000000000000000000000000000000000000dEaD), // LP 永久转黑洞
            deadline: block.timestamp + 300
        });

        positionManager.mint{value: ethLP}(params);

        emit LiquidityEngineTriggered(ethAmount, tokenLP, "ADAPTIVE_PUMP_AND_LP");
    }

    /**
     * @dev 内部工具方法：用 ETH 去 V3 执行 Swap 并打入黑洞销毁
     */
    function _swapEthForTokensAndBurn(uint256 ethAmount) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(uDOGE),
            fee: POOL_FEE,
            recipient: address(0x000000000000000000000000000000000000dEaD), // 换回的代币直接发往黑洞销毁
            deadline: block.timestamp + 300,
            amountIn: ethAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactInputSingle{value: ethAmount}(params);
    }

    /**
     * @dev 方案 B 退出机制：自适应偏离度退出税
     */
    function burn(uint256 tokenAmount) external nonReentrant {
        // --- Gas 预留检查：burnFrom + transfer 至少需要 6 万 Gas ---
        require(gasleft() >= 60_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for burn");
        require(block.number >= lastInteractionBlock[msg.sender] + COOLDOWN_BLOCKS, "uDOGE: Cooldown lock active");
        require(tokenAmount > 0, "uDOGE: Must burn tokens");

        // 1. 获取保底单价及 V3 市场价
        uint256 p_floor = getFloorPrice();
        uint256 p_v3    = getV3MarketPrice();

        // 保底价为 0 表示 reservePool 为 0 或流通量极异常，不允许 Burn（防无声失败）
        require(p_floor > 0, "uDOGE: Floor price is zero, burn disabled");

        // 2. 根据保底单价计算本次应退还的标准 ETH
        uint256 standardEthPayout = (tokenAmount * p_floor) / 10**18;
        
        uint256 totalAvailableReserve = reservePool;
        if (!isColdStartDone) {
            totalAvailableReserve = reservePool + operationPool;
        }
        require(totalAvailableReserve >= standardEthPayout, "uDOGE: Insufficient reserve liquidity");

        // 3. 计算 1% 基础手续费（记入抽奖池）
        uint256 baseFee = standardEthPayout / 100;
        jackpotPool += baseFee;

        // 4. 计算方案 B 惩罚性退出税（仅在 V3 价格跌破保底线且已开启冷启动时激活）
        uint256 penaltyFee = 0;
        if (isColdStartDone && p_v3 < p_floor && p_floor > 0) {
            // 惩罚率 = (1 - P_v3/P_floor) + 5%，硬顶 50%
            uint256 penaltyRate = 100 - ((p_v3 * 100) / p_floor) + 5;
            if (penaltyRate > 50) penaltyRate = 50;
            penaltyFee = (standardEthPayout * penaltyRate) / 100;
        }

        uint256 netPayout = standardEthPayout - baseFee - penaltyFee;

        // 5. 先销毁代币，再更新账本
        uDOGE.burnFrom(msg.sender, tokenAmount);
        
        if (!isColdStartDone) {
            // 如果还未开启冷启动（退本保障），按 50/50 比例从保底池和运作池中按比例扣减
            uint256 halfPayout = standardEthPayout / 2;
            reservePool -= halfPayout;
            operationPool -= (standardEthPayout - halfPayout);
        } else {
            reservePool -= standardEthPayout;
        }

        // 6. 罚金分配：50% 补入准备金抬高保底价，50% 入运作池拉升 V3 (冷启动后生效)
        if (penaltyFee > 0) {
            uint256 halfPenalty = penaltyFee / 2;
            reservePool   += halfPenalty;
            operationPool += penaltyFee - halfPenalty;
        }

        // 7. 转账 ETH 给用户，并重置冷却锁（防止连续 Burn 攻击）
        lastInteractionBlock[msg.sender] = block.number;
        payable(msg.sender).transfer(netPayout);

        emit BurnExecuted(msg.sender, tokenAmount, netPayout, penaltyFee);
    }

    /**
     * @dev 触发里程碑抽奖：
     *   1. 用抽奖池中积累 of ETH 去 V3 买入 uDOGE
     *   2. 将买回的 uDOGE 授权给 Staking 合约并通知其分配奖品
     */
    function distributeJackpot() external nonReentrant {
        // --- Gas 预留检查 ---
        require(gasleft() >= 150_000 + MIN_GAS_RESERVE, "uDOGE: Insufficient gas for jackpot");

        uint256 ethAmount = jackpotPool;
        require(ethAmount > 0, "uDOGE: No jackpot to distribute");

        // 先清零，防重入
        jackpotPool = 0;

        // 根据当前 V3 市场价估算最低可接受输出量（50% 容忍滑点），防三明治攻击
        uint256 p_v3 = getV3MarketPrice();
        uint256 minAmountOut = 0;
        if (p_v3 > 0) {
            uint256 expectedOut = (ethAmount * 10**18) / p_v3;
            minAmountOut = expectedOut / 2; // 接受最低 50% 的预估量，超出即 revert
        }

        // 用 ETH 从 V3 池子买入 uDOGE，接收方为本合约（后续再转给 Staking）
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

        // 授权 Staking 合约拉取奖励代币，再通知其执行摇号派奖
        uDOGE.approve(address(stakingContract), uDogeReceived);
        stakingContract.recordJackpotFeeInToken(uDogeReceived);

        emit JackpotDistributed(ethAmount, uDogeReceived);
    }

    /**
     * @dev 获取保底价：准备金 ETH 余额 / 代币流通量
     */
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

    /**
     * @dev 获取 V3 真实交易单价
     */
    function getV3MarketPrice() public view returns (uint256) {
        if (v3Pool == address(0)) return getFloorPrice();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(v3Pool).slot0();
        if (sqrtPriceX96 == 0) return getFloorPrice();

        // 1 uDOGE 单价折合多少 ETH (通过 Q96 计算转换)
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

    // 允许合约接收外部退还的 ETH
    receive() external payable {}
}
