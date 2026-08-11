// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./StandardTokenV2_ETH.sol";
import {PoolKey, PoolId, PoolIdLibrary, Currency, CurrencyLibrary} from "./interfaces/PoolKey.sol";
import {LPFeeLibrary} from "./interfaces/IHooks.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {Actions} from "./interfaces/Actions.sol";
import {TickMathLib} from "./interfaces/TickMathLib.sol";

// ──────────────────── External interfaces ────────────────────

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface IMoonsendFeeHook {
    function registerPool(PoolId poolId, uint24 fee) external;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

library SafeTransfer {
    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (ret.length == 0 || abi.decode(ret, (bool))), "!transfer");
    }
}

interface IFeeManagerV2 {
    function registerTokenInfo(
        uint256 positionId,
        address token,
        address creator,
        address pool,
        bool autoLock,
        uint16 poolFeePips,
        uint8  feeMode
    ) external;
}

// ──────────────────── ReentrancyGuard ────────────────────

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrant");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ──────────────────── TokenFactory_V2_ETH ────────────────────
//
// V2 WETH-paired factory for Ethereum. Same launch flow as the previous WETH
// factory but adds a per-token FeeMode (SPLIT_BOTH | ALL_ETH) that is
// forwarded to the V2 fee manager during registration. Frontend exposes the
// choice on the deploy form; the contract just routes it through.

contract TokenFactory_V2_ETH is ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    // ──────────────────── Uniswap V4 Addresses (Ethereum) ────────────────────
    address public constant POOL_MANAGER         = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant V4_POSITION_MANAGER  = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address public constant PERMIT2              = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ──────────────────── Token Addresses (Ethereum) ────────────────────
    address public constant WETH            = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC            = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_USDC_POOL  = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // ──────────────────── Mint Fee ────────────────────
    address public constant MINT_FEE_RECIPIENT = 0xB0dD6f16D098092B5660808A8444db9831569194;
    uint256 public constant MINT_FEE_BPS = 150;

    // ──────────────────── Deployment Constants ────────────────────
    uint256 public deploymentFee = 0;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MIN_DEV_BUY = 0.001 ether;
    uint256 public constant MAX_DEV_BUY = 5 ether;
    uint256 public constant MCAP_OPTION_1 = 4000 * 10**18;
    uint256 public constant MCAP_OPTION_2 = 8000 * 10**18;
    uint256 public constant MCAP_OPTION_3 = 12000 * 10**18;
    uint256 public constant MCAP_OPTION_4 = 16000 * 10**18;

    // FeeMode enum values mirror the fee manager
    uint8 public constant FEE_MODE_SPLIT_BOTH = 0;
    uint8 public constant FEE_MODE_ALL_ETH    = 1;

    // ──────────────────── State ────────────────────
    address public owner;
    address public factoryWallet;
    address public feeManager;     // renamed from lockerHelper for clarity
    address public hookAddress;
    bool    public autoSendToFeeManager;

    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => address[]) public creatorTokens;
    address[] public allTokens;

    mapping(address => uint256) public tokenToPositionId;
    mapping(uint256 => address) public positionIdToToken;
    mapping(address => PoolId)  public tokenToPoolId;
    mapping(address => uint8)   public tokenFeeMode;

    enum DeploymentMethod { ONESIDED_4K, ONESIDED_8K, ONESIDED_12K, ONESIDED_16K }

    struct TokenInfo {
        address creator;
        address pool;
        uint256 positionId;
        uint256 createdAt;
        uint256 liquidityETH;
        uint256 totalSupply;
        uint256 initialMcap;
        string  name;
        string  symbol;
        DeploymentMethod deployMethod;
        bool feesCollected;
        uint256 devBuyAmount;
        uint8   feeMode;
    }

    struct TokenMetadata {
        string imageUrl;
        string description;
        string website;
        string twitter;
        string telegram;
        string discord;
    }

    // ──────────────────── Events ────────────────────

    event TokenDeployed(
        address indexed token,
        address indexed creator,
        address pool,
        uint256 positionId,
        DeploymentMethod deployMethod,
        uint256 devBuyAmount,
        uint8 feeMode
    );

    event DevBuyExecuted(address indexed token, address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event DeploymentFeeChanged(uint256 oldFee, uint256 newFee);
    event FactoryWalletChanged(address indexed oldWallet, address indexed newWallet);
    event FeeManagerChanged(address indexed oldFM, address indexed newFM);
    event HookAddressChanged(address indexed oldHook, address indexed newHook);
    event AutoSendToFeeManagerChanged(bool enabled);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() { require(msg.sender == owner, "!owner"); _; }

    constructor() {
        owner = msg.sender;
        factoryWallet = 0x4C077f7D5c39514778b615D72c64097FFec32F64;
        feeManager = address(0);
        hookAddress = address(0);
        autoSendToFeeManager = false;
    }

    // ──────────────────── deployToken ────────────────────

    function deployToken(
        string memory name,
        string memory symbol,
        uint256 targetMarketCap,
        uint256 devBuyAmount,
        uint24  feePercent,
        uint8   feeMode,
        TokenMetadata memory metadata
    ) external payable nonReentrant returns (address token, address pool, uint256 positionId) {
        uint256 totalSupply = TOTAL_SUPPLY;
        _validateDeployment(name, symbol, targetMarketCap);
        require(
            feePercent == 13300 || feePercent == 20000 || feePercent == 27500 || feePercent == 34000 || feePercent == 42000,
            "!fee"
        );
        require(feeMode <= FEE_MODE_ALL_ETH, "!feeMode");
        require(hookAddress != address(0), "!hook");
        require(msg.value >= deploymentFee + devBuyAmount, "!payment");

        if (devBuyAmount > 0) {
            require(devBuyAmount >= MIN_DEV_BUY, "!min");
            require(devBuyAmount <= MAX_DEV_BUY, "!max");
        }

        token = address(new StandardTokenV2_ETH(
            name, symbol, totalSupply, address(this), msg.sender,
            metadata.imageUrl, metadata.description, metadata.website, metadata.twitter, metadata.telegram, metadata.discord
        ));

        pool = address(0);

        {
            uint256 liquidityAmount = totalSupply - (totalSupply * MINT_FEE_BPS) / 10000;
            StandardTokenV2_ETH(token).transfer(MINT_FEE_RECIPIENT, totalSupply - liquidityAmount);

            PoolKey memory poolKey = _createPoolWithMcap(token, totalSupply, targetMarketCap, feePercent);
            tokenToPoolId[token] = poolKey.toId();

            address mintTo = (autoSendToFeeManager && feeManager != address(0)) ? feeManager : address(this);
            positionId = _addOneSidedLiquidity(token, poolKey, totalSupply, liquidityAmount, targetMarketCap, mintTo);

            if (mintTo == feeManager) {
                _registerWithFeeManager(token, pool, positionId, feePercent, feeMode);
            }

            if (devBuyAmount > 0) {
                uint256 tokensBought = _executeDevBuy(token, poolKey, devBuyAmount);
                emit DevBuyExecuted(token, msg.sender, devBuyAmount, tokensBought);
            }
        }

        _storeTokenInfo(token, pool, positionId, totalSupply, targetMarketCap, devBuyAmount, feeMode);
        _storeMappings(token, positionId, feeMode);

        {
            uint256 excess = msg.value - deploymentFee - devBuyAmount;
            if (excess > 0) {
                (bool refunded, ) = msg.sender.call{value: excess}("");
                require(refunded, "!refund");
            }
        }

        emit TokenDeployed(token, msg.sender, pool, positionId, _getDeploymentMethod(targetMarketCap), devBuyAmount, feeMode);
        return (token, pool, positionId);
    }

    // ──────────────────── Pool Creation (V4 with WETH) ────────────────────

    function _createPoolWithMcap(
        address token,
        uint256 totalSupply,
        uint256 targetMcap,
        uint24 feePercent
    ) private returns (PoolKey memory poolKey) {
        bool wethIsToken0 = WETH < token;
        (address c0, address c1) = wethIsToken0 ? (WETH, token) : (token, WETH);

        poolKey = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(200),
            hooks: hookAddress
        });

        PoolId poolId = poolKey.toId();
        IMoonsendFeeHook(hookAddress).registerPool(poolId, feePercent);

        uint256 ethPrice = getCurrentETHPrice();
        uint160 sqrtPriceX96 = TickMathLib.calculateMcapSqrtPrice(wethIsToken0, totalSupply, targetMcap, ethPrice);

        IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96);
        return poolKey;
    }

    // ──────────────────── Liquidity Minting (V4) ────────────────────

    function _addOneSidedLiquidity(
        address token,
        PoolKey memory poolKey,
        uint256 totalSupply,
        uint256 liquidityAmount,
        uint256 targetMarketCap,
        address mintTo
    ) private returns (uint256 positionId) {
        bool wethIsToken0 = Currency.unwrap(poolKey.currency0) == WETH;

        StandardTokenV2_ETH(token).approve(PERMIT2, liquidityAmount);
        IPermit2(PERMIT2).approve(token, V4_POSITION_MANAGER, uint160(liquidityAmount), uint48(block.timestamp + 3600));

        (int24 tickLower, int24 tickUpper, ,) =
            _prepareOneSidedParams(totalSupply, targetMarketCap, wethIsToken0);

        Currency tokenCurrency = wethIsToken0 ? poolKey.currency1 : poolKey.currency0;

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE),
            uint8(Actions.MINT_POSITION_FROM_DELTAS),
            uint8(Actions.CLOSE_CURRENCY),
            uint8(Actions.CLOSE_CURRENCY)
        );

        (uint128 amt0Max, uint128 amt1Max) = wethIsToken0
            ? (uint128(0), uint128(liquidityAmount))
            : (uint128(liquidityAmount), uint128(0));

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(tokenCurrency, liquidityAmount, true);
        params[1] = abi.encode(poolKey, tickLower, tickUpper, amt0Max, amt1Max, mintTo, bytes(""));
        params[2] = abi.encode(poolKey.currency0);
        params[3] = abi.encode(poolKey.currency1);

        IPositionManager(V4_POSITION_MANAGER).modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 300
        );

        positionId = IPositionManager(V4_POSITION_MANAGER).nextTokenId() - 1;
    }

    function _prepareOneSidedParams(
        uint256 totalSupply,
        uint256 targetMarketCap,
        bool wethIsToken0
    ) private view returns (int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired) {
        int24 tickSpacing = int24(200);
        int24 OPTIMIZED_TICK_RANGE = TickMathLib.getOptimalTickRange(targetMarketCap, MCAP_OPTION_1, MCAP_OPTION_2, MCAP_OPTION_3);

        uint256 ethPrice = getCurrentETHPrice();
        int24 currentTick = TickMathLib.getInitialTick(totalSupply, targetMarketCap, tickSpacing, ethPrice, wethIsToken0);

        if (wethIsToken0) {
            tickUpper = ((currentTick / tickSpacing) * tickSpacing) - tickSpacing;
            tickLower = tickUpper - OPTIMIZED_TICK_RANGE;
            if (tickLower < -887200) tickLower = -887200;
            amount0Desired = 0;
            amount1Desired = totalSupply;
        } else {
            tickLower = ((currentTick / tickSpacing) * tickSpacing) + tickSpacing;
            tickUpper = tickLower + OPTIMIZED_TICK_RANGE;
            if (tickUpper > 887200) tickUpper = 887200;
            amount0Desired = totalSupply;
            amount1Desired = 0;
        }
    }

    // ──────────────────── Dev Buy ────────────────────

    function _executeDevBuy(address token, PoolKey memory poolKey, uint256 ethAmount) private returns (uint256) {
        uint256 factoryTokenBefore = StandardTokenV2_ETH(token).balanceOf(address(this));
        IWETH(WETH).deposit{value: ethAmount}();
        bytes memory callbackData = abi.encode(token, poolKey, ethAmount);
        IPoolManager(POOL_MANAGER).unlock(callbackData);
        uint256 bought = StandardTokenV2_ETH(token).balanceOf(address(this)) - factoryTokenBefore;
        if (bought > 0) StandardTokenV2_ETH(token).transfer(msg.sender, bought);
        return bought;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == POOL_MANAGER, "!pm");

        (address token, PoolKey memory poolKey, uint256 ethAmount) = abi.decode(data, (address, PoolKey, uint256));
        require(poolKey.hooks == hookAddress, "!hook");

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == WETH;

        int256 swapDelta;
        {
            IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(ethAmount),
                sqrtPriceLimitX96: zeroForOne
                    ? uint160(4295128740)
                    : uint160(1461446703485210103287273052203988822378723970341)
            });
            swapDelta = IPoolManager(POOL_MANAGER).swap(poolKey, sp, bytes(""));
        }

        int128 delta0 = int128(swapDelta >> 128);
        int128 delta1 = int128(swapDelta);

        uint256 wethOwed = uint256(-(zeroForOne ? int256(delta0) : int256(delta1)));
        IPoolManager(POOL_MANAGER).sync(WETH);
        SafeTransfer.safeTransfer(WETH, POOL_MANAGER, wethOwed);
        IPoolManager(POOL_MANAGER).settle();

        uint256 tokensOwed = uint256(zeroForOne ? int256(delta1) : int256(delta0));
        IPoolManager(POOL_MANAGER).take(token, address(this), tokensOwed);

        return bytes("");
    }

    // ──────────────────── Storage / registration ────────────────────

    function _storeMappings(address token, uint256 positionId, uint8 feeMode) private {
        tokenToPositionId[token] = positionId;
        positionIdToToken[positionId] = token;
        tokenFeeMode[token] = feeMode;
        creatorTokens[msg.sender].push(token);
        allTokens.push(token);
    }

    function _storeTokenInfo(
        address token,
        address pool,
        uint256 positionId,
        uint256 totalSupply,
        uint256 targetMarketCap,
        uint256 devBuyAmount,
        uint8   feeMode
    ) private {
        TokenInfo storage info = tokenInfo[token];
        info.creator = msg.sender;
        info.pool = pool;
        info.positionId = positionId;
        info.createdAt = block.timestamp;
        info.liquidityETH = 0;
        info.totalSupply = totalSupply;
        info.initialMcap = targetMarketCap;
        info.name = StandardTokenV2_ETH(token).name();
        info.symbol = StandardTokenV2_ETH(token).symbol();
        info.deployMethod = _getDeploymentMethod(targetMarketCap);
        info.feesCollected = false;
        info.devBuyAmount = devBuyAmount;
        info.feeMode = feeMode;
    }

    function _registerWithFeeManager(
        address token,
        address pool,
        uint256 positionId,
        uint24  feePercent,
        uint8   feeMode
    ) private {
        IFeeManagerV2(feeManager).registerTokenInfo(
            positionId,
            token,
            msg.sender,
            pool,
            true,
            uint16(feePercent),
            feeMode
        );
    }

    // ──────────────────── Validation & Helpers ────────────────────

    function _validateDeployment(
        string memory name,
        string memory symbol,
        uint256 targetMarketCap
    ) private pure {
        require(
            targetMarketCap == MCAP_OPTION_1 ||
            targetMarketCap == MCAP_OPTION_2 ||
            targetMarketCap == MCAP_OPTION_3 ||
            targetMarketCap == MCAP_OPTION_4,
            "Invalid market cap"
        );
        require(bytes(name).length > 0   && bytes(name).length   <= 50, "!name");
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 10, "!symbol");
    }

    function _getDeploymentMethod(uint256 targetMarketCap) private pure returns (DeploymentMethod) {
        if (targetMarketCap == MCAP_OPTION_1) return DeploymentMethod.ONESIDED_4K;
        if (targetMarketCap == MCAP_OPTION_2) return DeploymentMethod.ONESIDED_8K;
        if (targetMarketCap == MCAP_OPTION_3) return DeploymentMethod.ONESIDED_12K;
        return DeploymentMethod.ONESIDED_16K;
    }

    // ──────────────────── Price / Tick Math ────────────────────

    function getCurrentETHPrice() public view returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(WETH_USDC_POOL);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        if (sqrtPriceX96 == 0) return 3000 * 10**18;
        uint256 numer = (uint256(10**15) << 96) / uint256(sqrtPriceX96);
        return numer * numer;
    }

    // ──────────────────── Admin ────────────────────

    function setFactoryWallet(address _factoryWallet) external onlyOwner {
        address old = factoryWallet;
        factoryWallet = _factoryWallet;
        emit FactoryWalletChanged(old, _factoryWallet);
    }

    function setFeeManager(address _feeManager) external onlyOwner {
        address old = feeManager;
        feeManager = _feeManager;
        emit FeeManagerChanged(old, _feeManager);
    }

    function setHookAddress(address _hook) external onlyOwner {
        address old = hookAddress;
        hookAddress = _hook;
        emit HookAddressChanged(old, _hook);
    }

    function setAutoSendToFeeManager(bool _autoSend) external onlyOwner {
        autoSendToFeeManager = _autoSend;
        emit AutoSendToFeeManagerChanged(_autoSend);
    }

    function setDeploymentFee(uint256 _newFee) external onlyOwner {
        uint256 oldFee = deploymentFee;
        deploymentFee = _newFee;
        emit DeploymentFeeChanged(oldFee, _newFee);
    }

    function withdrawETH() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "!balance");
        (bool sent, ) = owner.call{value: balance}("");
        require(sent, "!send");
    }

    function withdrawToken(address tokenAddress, uint256 amount) external onlyOwner nonReentrant {
        SafeTransfer.safeTransfer(tokenAddress, owner, amount);
    }

    function rescueERC721(address nftContract, address to, uint256 tokenId) external onlyOwner {
        (bool success, ) = nftContract.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), to, tokenId)
        );
        require(success, "!nft");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "!owner");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // ──────────────────── Views ────────────────────

    function getCreatorTokens(address creator) external view returns (address[] memory) {
        return creatorTokens[creator];
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function getTokenDetails(address token) external view returns (TokenInfo memory) {
        TokenInfo memory info = tokenInfo[token];
        require(info.creator != address(0), "!token");
        return info;
    }

    receive() external payable {}
}
