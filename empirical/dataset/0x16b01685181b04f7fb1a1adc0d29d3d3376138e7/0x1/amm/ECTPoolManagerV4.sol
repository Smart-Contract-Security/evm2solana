// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IHooks} from "./IHooks.sol";

contract ECTPoolManagerV4 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error IdenticalTokens();
    error PoolExists();
    error PoolMissing();
    error MustContainECT();
    error InvalidLpFee();
    error InsufficientLiquidity();
    error InsufficientOutput();
    error HookRejected();
    error LpFeeOverrideTooHigh();

    uint16 public constant PROTOCOL_FEE_TREASURY_BPS = 100; // 1.00%
    uint16 public constant PROTOCOL_FEE_CREATOR_BPS  = 50;  // 0.50%
    uint16 public constant PROTOCOL_FEE_TOTAL_BPS    = 150; // 1.50%
    uint16 public constant MAX_LP_FEE_BPS = 1_000;          // 10% hard cap
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant MAX_LP_FEE_OVERRIDE_BPS = 5_000; // 50% cap on hook override

    uint256 public constant POOL_CREATION_FEE = 100 * 1e18;

    IERC20 public immutable ect;
    address public treasury;

    mapping(bytes32 => Pool) public pools;
    bytes32[] public allPoolIds;
    mapping(address => address) public tokenCreator;

    struct Pool {
        address token0;
        address token1;
        uint16 lpFeeBps;
        address hook;
        address creatorRecipient;
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalLiquidity;
        bool initialized;
    }

    mapping(bytes32 => mapping(address => uint256)) public liquidityOf;

    event PoolCreated(bytes32 indexed poolId, address indexed token0, address indexed token1, uint16 lpFeeBps, address hook);
    event LiquidityAdded(bytes32 indexed poolId, address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(bytes32 indexed poolId, address indexed provider, uint256 liquidity, uint256 amount0, uint256 amount1);
    event SwapExecuted(bytes32 indexed poolId, address indexed sender, bool zeroForOne, uint256 amountIn, uint256 amountOut);
    event ProtocolFeePaid(bytes32 indexed poolId, address token, uint256 treasuryFee, uint256 creatorFee);
    event HookCalled(bytes32 indexed poolId, address hook, bytes4 selector);

    constructor(address initialOwner, address _ect, address _treasury) Ownable(initialOwner) {
        if (_ect == address(0) || _treasury == address(0)) revert ZeroAddress();
        ect = IERC20(_ect);
        treasury = _treasury;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
    }

    function registerTokenCreator(address token, address creator) external onlyOwner {
        tokenCreator[token] = creator;
    }

    function allPoolsLength() external view returns (uint256) {
        return allPoolIds.length;
    }

    function poolIdFor(address tokenA, address tokenB, uint16 lpFeeBps, address hook)
        public
        pure
        returns (bytes32)
    {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(t0, t1, lpFeeBps, hook));
    }

    function getPool(bytes32 poolId) external view returns (Pool memory) {
        return pools[poolId];
    }

    /// @notice Create an ECT / token V4 pool.
    function createPool(address token, uint16 lpFeeBps, address hook)
        external
        returns (bytes32 poolId)
    {
        return _createPoolInternal(address(ect), token, lpFeeBps, hook);
    }

    /// @notice Create a V4 pool between any two ERC-20s, with an optional hook.
    /// @param  tokenA       First token.
    /// @param  tokenB       Second token (different from tokenA).
    /// @param  lpFeeBps     LP fee in basis points, 0..MAX_LP_FEE_BPS.
    /// @param  hook         Hook contract (address(0) for none).
    /// @return poolId       The pool id.
    function createPoolPair(address tokenA, address tokenB, uint16 lpFeeBps, address hook)
        external
        returns (bytes32 poolId)
    {
        return _createPoolInternal(tokenA, tokenB, lpFeeBps, hook);
    }

    function _createPoolInternal(address tokenA, address tokenB, uint16 lpFeeBps, address hook)
        internal
        returns (bytes32 poolId)
    {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (tokenA == tokenB) revert IdenticalTokens();
        if (lpFeeBps > MAX_LP_FEE_BPS) revert InvalidLpFee();

        poolId = poolIdFor(tokenA, tokenB, lpFeeBps, hook);
        if (pools[poolId].initialized) revert PoolExists();

        ect.safeTransferFrom(msg.sender, treasury, POOL_CREATION_FEE);

        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        address nonEct = tokenA == address(ect) ? tokenB : tokenA;
        address creator = tokenCreator[nonEct];
        pools[poolId] = Pool({
            token0: t0,
            token1: t1,
            lpFeeBps: lpFeeBps,
            hook: hook,
            creatorRecipient: creator == address(0) ? treasury : creator,
            reserve0: 0,
            reserve1: 0,
            totalLiquidity: 0,
            initialized: true
        });
        allPoolIds.push(poolId);

        if (hook != address(0)) {
            IHooks.Permissions memory perms = IHooks(hook).getHookPermissions();
            if (perms.beforeInitialize) {
                bytes4 sel = IHooks(hook).beforeInitialize(msg.sender, poolId, 0);
                emit HookCalled(poolId, hook, sel);
            }
            if (perms.afterInitialize) {
                bytes4 sel = IHooks(hook).afterInitialize(msg.sender, poolId, 0);
                emit HookCalled(poolId, hook, sel);
            }
        }

        emit PoolCreated(poolId, t0, t1, lpFeeBps, hook);
    }

    function addLiquidity(bytes32 poolId, uint256 amount0, uint256 amount1)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        Pool storage p = pools[poolId];
        if (!p.initialized) revert PoolMissing();

        if (p.hook != address(0)) {
            IHooks.Permissions memory perms = IHooks(p.hook).getHookPermissions();
            if (perms.beforeAddLiquidity) {
                bytes4 sel = IHooks(p.hook).beforeAddLiquidity(msg.sender, poolId, amount0, amount1);
                emit HookCalled(poolId, p.hook, sel);
            }
        }

        if (amount0 > 0) IERC20(p.token0).safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) IERC20(p.token1).safeTransferFrom(msg.sender, address(this), amount1);

        if (p.totalLiquidity == 0) {
            // First mint: liquidity = amount0 + amount1 minus dust burn.
            liquidity = amount0 + amount1;
            if (liquidity < 1000) revert InsufficientLiquidity();
            liquidity -= 1000;
            p.totalLiquidity = liquidity + 1000;
        } else {
            uint256 l0 = (amount0 * p.totalLiquidity) / p.reserve0;
            uint256 l1 = (amount1 * p.totalLiquidity) / p.reserve1;
            liquidity = l0 < l1 ? l0 : l1;
            p.totalLiquidity += liquidity;
        }
        if (liquidity == 0) revert InsufficientLiquidity();

        liquidityOf[poolId][msg.sender] += liquidity;
        p.reserve0 += amount0;
        p.reserve1 += amount1;

        if (p.hook != address(0)) {
            IHooks.Permissions memory perms2 = IHooks(p.hook).getHookPermissions();
            if (perms2.afterAddLiquidity) {
                bytes4 sel = IHooks(p.hook).afterAddLiquidity(msg.sender, poolId, amount0, amount1);
                emit HookCalled(poolId, p.hook, sel);
            }
        }

        emit LiquidityAdded(poolId, msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(bytes32 poolId, uint256 liquidity)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        Pool storage p = pools[poolId];
        if (!p.initialized) revert PoolMissing();
        if (liquidity == 0 || liquidityOf[poolId][msg.sender] < liquidity) revert InsufficientLiquidity();

        if (p.hook != address(0)) {
            IHooks.Permissions memory perms = IHooks(p.hook).getHookPermissions();
            if (perms.beforeRemoveLiquidity) {
                bytes4 sel = IHooks(p.hook).beforeRemoveLiquidity(msg.sender, poolId, liquidity);
                emit HookCalled(poolId, p.hook, sel);
            }
        }

        amount0 = (liquidity * p.reserve0) / p.totalLiquidity;
        amount1 = (liquidity * p.reserve1) / p.totalLiquidity;
        liquidityOf[poolId][msg.sender] -= liquidity;
        p.totalLiquidity -= liquidity;
        p.reserve0 -= amount0;
        p.reserve1 -= amount1;
        if (amount0 > 0) IERC20(p.token0).safeTransfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(p.token1).safeTransfer(msg.sender, amount1);

        if (p.hook != address(0)) {
            IHooks.Permissions memory perms2 = IHooks(p.hook).getHookPermissions();
            if (perms2.afterRemoveLiquidity) {
                bytes4 sel = IHooks(p.hook).afterRemoveLiquidity(msg.sender, poolId, liquidity);
                emit HookCalled(poolId, p.hook, sel);
            }
        }

        emit LiquidityRemoved(poolId, msg.sender, liquidity, amount0, amount1);
    }

    function swap(bytes32 poolId, bool zeroForOne, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        Pool storage p = pools[poolId];
        if (!p.initialized) revert PoolMissing();
        if (amountIn == 0) revert InsufficientLiquidity();

        uint16 lpFeeBps = _runBeforeSwap(p, poolId, zeroForOne, amountIn);

        address tokenIn = zeroForOne ? p.token0 : p.token1;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 afterProtocol = _payProtocolFee(poolId, p, tokenIn, amountIn);

        // LP fee stays in reserves.
        uint256 amountInForSwap = afterProtocol - (afterProtocol * lpFeeBps) / BPS_DENOMINATOR;
        amountOut = _doSwap(p, zeroForOne, afterProtocol, amountInForSwap, minAmountOut);

        IERC20(zeroForOne ? p.token1 : p.token0).safeTransfer(recipient, amountOut);

        _runAfterSwap(p, poolId, zeroForOne, amountIn, amountOut);
        emit SwapExecuted(poolId, msg.sender, zeroForOne, amountIn, amountOut);
    }

    function _runBeforeSwap(Pool storage p, bytes32 poolId, bool zeroForOne, uint256 amountIn)
        private
        returns (uint16 lpFeeBps)
    {
        lpFeeBps = p.lpFeeBps;
        if (p.hook == address(0)) return lpFeeBps;
        IHooks.Permissions memory perms = IHooks(p.hook).getHookPermissions();
        if (!perms.beforeSwap) return lpFeeBps;
        (bytes4 sel, uint16 overrideBps) = IHooks(p.hook).beforeSwap(msg.sender, poolId, zeroForOne, amountIn);
        emit HookCalled(poolId, p.hook, sel);
        if (overrideBps > 0) {
            if (overrideBps > MAX_LP_FEE_OVERRIDE_BPS) revert LpFeeOverrideTooHigh();
            lpFeeBps = overrideBps;
        }
    }

    function _payProtocolFee(bytes32 poolId, Pool storage p, address tokenIn, uint256 amountIn)
        private
        returns (uint256 afterProtocol)
    {
        uint256 treasuryFee = (amountIn * PROTOCOL_FEE_TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 creatorFee = (amountIn * PROTOCOL_FEE_CREATOR_BPS) / BPS_DENOMINATOR;
        if (treasuryFee > 0) IERC20(tokenIn).safeTransfer(treasury, treasuryFee);
        if (creatorFee > 0) IERC20(tokenIn).safeTransfer(p.creatorRecipient, creatorFee);
        emit ProtocolFeePaid(poolId, tokenIn, treasuryFee, creatorFee);
        afterProtocol = amountIn - treasuryFee - creatorFee;
    }

    function _doSwap(Pool storage p, bool zeroForOne, uint256 afterProtocol, uint256 amountInForSwap, uint256 minAmountOut)
        private
        returns (uint256 amountOut)
    {
        uint256 rIn = zeroForOne ? p.reserve0 : p.reserve1;
        uint256 rOut = zeroForOne ? p.reserve1 : p.reserve0;
        if (rIn == 0 || rOut == 0) revert InsufficientLiquidity();
        amountOut = (amountInForSwap * rOut) / (rIn + amountInForSwap);
        if (amountOut < minAmountOut) revert InsufficientOutput();
        if (amountOut >= rOut) revert InsufficientLiquidity();

        if (zeroForOne) {
            p.reserve0 = rIn + afterProtocol;
            p.reserve1 = rOut - amountOut;
        } else {
            p.reserve1 = rIn + afterProtocol;
            p.reserve0 = rOut - amountOut;
        }
    }

    function _runAfterSwap(Pool storage p, bytes32 poolId, bool zeroForOne, uint256 amountIn, uint256 amountOut)
        private
    {
        if (p.hook == address(0)) return;
        IHooks.Permissions memory perms = IHooks(p.hook).getHookPermissions();
        if (!perms.afterSwap) return;
        bytes4 sel = IHooks(p.hook).afterSwap(msg.sender, poolId, zeroForOne, amountIn, amountOut);
        emit HookCalled(poolId, p.hook, sel);
    }

    function getAmountOut(bytes32 poolId, bool zeroForOne, uint256 amountIn) external view returns (uint256) {
        Pool storage p = pools[poolId];
        if (!p.initialized) return 0;
        uint256 afterProtocol = (amountIn * (BPS_DENOMINATOR - PROTOCOL_FEE_TOTAL_BPS)) / BPS_DENOMINATOR;
        uint256 afterLp = (afterProtocol * (BPS_DENOMINATOR - p.lpFeeBps)) / BPS_DENOMINATOR;
        uint256 rIn = zeroForOne ? p.reserve0 : p.reserve1;
        uint256 rOut = zeroForOne ? p.reserve1 : p.reserve0;
        if (rIn == 0 || rOut == 0) return 0;
        return (afterLp * rOut) / (rIn + afterLp);
    }
}
