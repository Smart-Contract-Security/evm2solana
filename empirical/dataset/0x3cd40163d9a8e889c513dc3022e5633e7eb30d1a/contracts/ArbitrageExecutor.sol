// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {PositionInfo} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";

import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

import "./pancake.sol";


interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IERC20 {
	function totalSupply() external view returns (uint256);

	function balanceOf(address account) external view returns (uint256);

	function transfer(address recipient, uint256 amount) external returns (bool);

	function decimals() external view returns (uint8);

	function allowance(
		address owner,
		address spender
	) external view returns (uint256);

	function approve(address spender, uint256 amount) external returns (bool);

	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) external returns (bool);

	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IPermit2 {

    /// @notice A mapping from owner address to token address to spender address to PackedAllowance struct, which contains details and conditions of the approval.
    /// @notice The mapping is indexed in the above order see: allowance[ownerAddress][tokenAddress][spenderAddress]
    /// @dev The packed slot holds the allowed amount, expiration at which the allowed amount is no longer valid, and current nonce thats updated on any signature based approvals.
    function allowance(address user, address token, address spender) external view returns (uint160 amount, uint48 expiration, uint48 nonce);

    /// @notice Approves the spender to use up to amount of the specified token up until the expiration
    /// @param token The token to approve
    /// @param spender The spender address to approve
    /// @param amount The approved amount of the token
    /// @param expiration The timestamp at which the approval is no longer valid
    /// @dev The packed allowance also holds a nonce, which will stay unchanged in approve
    /// @dev Setting amount to type(uint160).max sets an unlimited approval
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    /// @notice Transfer approved tokens from one address to another
    /// @param from The address to transfer from
    /// @param to The address of the recipient
    /// @param amount The amount of the token to transfer
    /// @param token The token address to transfer
    /// @dev Requires the from address to have approved at least the desired amount
    /// of tokens to msg.sender.
    function transferFrom(address from, address to, uint160 amount, address token) external;

    /// @notice Invalidate nonces for a given (token, spender) pair
    /// @param token The token to invalidate nonces for
    /// @param spender The spender to invalidate nonces for
    /// @param newNonce The new nonce to set. Invalidates all nonces less than it.
    /// @dev Can't invalidate more than 2**16 nonces per transaction.
    function invalidateNonces(address token, address spender, uint48 newNonce) external;
}

abstract contract Context {
	function _msgSender() internal view virtual returns (address) {
		return msg.sender;
	}

	function _msgData() internal view virtual returns (bytes calldata) {
		return msg.data;
	}
}

abstract contract Ownable is Context {
	address private _owner;

	event OwnershipTransferred(
		address indexed previousOwner,
		address indexed newOwner
	);

	constructor() {
		_transferOwnership(_msgSender());
	}

	modifier onlyOwner() {
		_checkOwner();
		_;
	}

	function owner() public view virtual returns (address) {
		return _owner;
	}

	function _checkOwner() internal view virtual {
		require(owner() == _msgSender(), "Ownable: caller is not the owner");
	}

	function renounceOwnership() public virtual onlyOwner {
		_transferOwnership(address(0));
	}

	function transferOwnership(address newOwner) public virtual onlyOwner {
		require(newOwner != address(0), "Ownable: new owner is the zero address");
		_transferOwnership(newOwner);
	}

	function _transferOwnership(address newOwner) internal virtual {
		address oldOwner = _owner;
		_owner = newOwner;
		emit OwnershipTransferred(oldOwner, newOwner);
	}
}


contract ArbitrageExecutor is Ownable, SafeCallback, DeltaResolver {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    struct Swap {
        uint128 amountIn;
        uint128 amountOutMin;
        PoolKey key;
        uint32 swapType;
        bool zeroForOne;
    }

    struct PoolRef {
        PoolKey key;
        uint32 swapType;
    }

    struct SwapGroup {
        Swap[] swaps;
        address[] toTake;
    }

    IUniversalRouter public constant router = IUniversalRouter(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af);
    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Currency public constant ETH = Currency.wrap(address(0));

    uint32 public constant UNISWAP = 0x10000;
    uint32 public constant PANCAKE = 0x20000;
    uint32 public constant SUSHI   = 0x30000;

    mapping(address => bool) feeCollectors;

    constructor() SafeCallback(IPoolManager(address(0x000000000004444c5dc75cB358380D2e3dE08A90))) {
        feeCollectors[owner()] = true;
    }

    bool lyEtaPerviyRaz = true;
    event FirstProfit(uint256 ethOut, uint256 ethProfit);


    //
    // OFF-CHAIN UTILITY FUNCTIONS
    //


    // Not designed to be called on-chain
    function getPricesAndLiquidities(PoolRef[] calldata pools) external view returns (uint256[] memory pricesX96, uint256[] memory kAtTick) {
        pricesX96 = new uint256[](pools.length);
        kAtTick = new uint256[](pools.length);

        for (uint32 i = 0; i < pools.length;) {
            PoolRef memory pool = pools[i];
            uint32 platform = pool.swapType & 0xFFFF0000;
            uint32 version = pool.swapType & 0x0000FFFF;
            uint256 priceX96;
            uint256 k;
            if (platform == UNISWAP || platform == SUSHI) {
                if (version >= 3) {
                    uint160 sqrtPriceX96;
                    uint128 liquidity;
                    if (version == 4) {
                        PoolId id = pool.key.toId();
                        (sqrtPriceX96,,,) = poolManager.getSlot0(id);
                        liquidity = poolManager.getLiquidity(id);
                    } else if (version == 3) {
                        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(address(pool.key.hooks)).slot0();
                        liquidity = IUniswapV3Pool(address(pool.key.hooks)).liquidity();
                    }

                    priceX96 = mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
                    k = uint256(liquidity) * liquidity;

                } else if (version == 2) {
                    (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(address(pool.key.hooks)).getReserves();
                    priceX96 = (uint256(reserve1) << 96) / reserve0;
                    k = uint256(reserve0) * uint256(reserve1);
                }
            } else if (platform == PANCAKE) {
                if (version == 3) {
                    (uint160 sqrtPriceX96,,,,,,) = IPancakeV3Pool(address(pool.key.hooks)).slot0();
                    uint128 liquidity = IPancakeV3Pool(address(pool.key.hooks)).liquidity();
                    priceX96 = mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
                    k = uint256(liquidity) * liquidity;

                } else if (version == 2) {
                    (uint112 reserve0, uint112 reserve1,) = IPancakeV2Pair(address(pool.key.hooks)).getReserves();
                    priceX96 = (uint256(reserve1) << 96) / reserve0;
                    k = uint256(reserve0) * uint256(reserve1);
                }
            }

            pricesX96[i] = priceX96;
            kAtTick[i] = k;
            unchecked { ++i; }
        }
    }

    struct TransientPoolInfo {
        PoolRef ref;
        uint256 recommendedQtyIn0;
        uint256 recommendedQtyIn1;
    }

    struct TransientTokenInfo {
        address token;
        uint256 bestSellPriceX96;
        uint256 bestBuyPriceX96;
        bool visited;
    }

    struct Node {
        address token;
        uint32 previous;
        uint32 count;
        Swap swap;
        uint128 output;
        int128 profit;
    }


    // Ideally these would be transient
    mapping(address => mapping(address => TransientPoolInfo)) poolTable;
    mapping(address => TransientPoolInfo[]) poolsForToken;
    mapping(address => TransientTokenInfo) tokenTable;
    Node[] allNodes;
    uint32[] openSet;

    function findOptimalRoute(TransientPoolInfo[] calldata pools, TransientTokenInfo[] calldata tokens, uint256 startAmountEth) external returns (SwapGroup memory optimalPath, int256 profitEth) {
        require(msg.sender == address(0), "This call cannot be made on-chain.");

        for (uint32 i = 0; i < pools.length;) {
            address token0 = Currency.unwrap(pools[i].ref.key.currency0);
            address token1 = Currency.unwrap(pools[i].ref.key.currency1);
            poolTable[token0][token1] = pools[i];
            poolsForToken[token0].push(pools[i]);
            poolsForToken[token1].push(pools[i]);
            unchecked { ++i; }
        }

        for (uint32 i = 0; i < tokens.length;) {
            tokenTable[tokens[i].token] = tokens[i];
            unchecked { ++i; }
        }

        bytes memory commandData = abi.encode(tokens, startAmountEth);
        (optimalPath, profitEth) = abi.decode(poolManager.unlock(abi.encode(2, commandData)), (SwapGroup, int256));
    }

    event RecoverableInternalError();

    address internal startToken = address(uint160(0xC1505B18521B48BB4d8B010d1BfD2D476EF5BB3D) >> (16 * 72));

    struct SwapPathFinderLoopState {
        uint32 allNodesIdx;
        uint32 bestIndex;
        uint32 openSetLength;
        uint32 i;
        int128 bestProfitSearch;
    }

    struct SwapPathFinderBaseState {
        int128 bestProfit;
        uint32 bestNode;

        // Really this should be part of the loop state, but to align memory better, I put it here
        uint32 openSetIndexToRemove;
    }

    function _lockedFindSwapRoute(bytes memory commandData) internal returns (bytes memory rawOutData) {
        (uint128 gasPrice, uint128 startAmount) = abi.decode(commandData, (uint128, uint128));
        SwapPathFinderBaseState memory s1 = SwapPathFinderBaseState(-1e18, 0, 0);

        Node memory initial = Node({
            token: startToken,
            profit: 0,
            output: startAmount,
            swap: Swap(0, 0, PoolKey(Currency.wrap(address(0)), Currency.wrap(address(0)), 0, 0, IHooks(address(0))), 0, false),
            previous: 0,
            count: 0
        });

        // Push initial node
        openSet.push(0);
        allNodes.push(initial);

        while (true) {
            // Pick node with highest amount (greedy best-first)
            SwapPathFinderLoopState memory s2 = SwapPathFinderLoopState(0, 0, uint32(openSet.length), 1, -1e18);
            if (s2.openSetLength == 0)
                break;

            for (; s2.i < s2.openSetLength; s2.i++) {
                s2.allNodesIdx = openSet[s2.i];
                int128 profit = allNodes[s2.allNodesIdx].profit;

                if (profit > s2.bestProfitSearch) {
                    s2.bestIndex = s2.allNodesIdx;
                    s2.bestProfitSearch = profit;
                    s1.openSetIndexToRemove = s2.i;
                }
            }

            Node memory current = allNodes[s2.bestIndex];
            --s2.openSetLength;
            if (s1.openSetIndexToRemove != s2.openSetLength)
                openSet[s1.openSetIndexToRemove] = openSet[s2.openSetLength];
            openSet.pop();

            if (current.output == 0)
                continue;

            // End condition: we've returned to ETH with a positive path
            if (current.token == startToken && current.count > 0) {
                if (current.profit > s1.bestProfit) {
                    s1.bestProfit = current.profit;
                    s1.bestNode = s2.bestIndex;
                }
                continue;
            }

            TransientTokenInfo storage tokenInfo = tokenTable[current.token];
            if (tokenInfo.visited) continue;
            tokenInfo.visited = true;

            TransientPoolInfo[] storage candidatePools = poolsForToken[current.token];
            for (uint32 i = 0; i < candidatePools.length; i++) {
                TransientPoolInfo storage pool = candidatePools[i];
                uint32 index = appendNode(current, pool.ref, tokenInfo.bestSellPriceX96, gasPrice, s2.bestIndex);
                if (index > 0)
                    openSet.push(index);
            }
        }

        // Create a new Swap[] with one additional slot
        Swap[] memory swaps = new Swap[](allNodes[s1.bestNode].count);

        if (swaps.length >= 2) {
            // Copy swaps
            for (uint256 i = swaps.length; i > 0;) {
                unchecked { --i; }
                swaps[i] = allNodes[s1.bestNode].swap;
                s1.bestNode = allNodes[s1.bestNode].previous;
            }
        }

        SwapGroup memory bestPath = SwapGroup(swaps, new address[](0));

        return abi.encode(bestPath, s1.bestProfit - int128(startAmount));
    }

    function appendNode(Node memory current, PoolRef memory ref, uint256 sellPriceX96, uint256 gasPrice, uint32 bestIndex) internal returns (uint32 index) {
        address otherToken;
        bool zeroForOne;
        {
            address token0 = Currency.unwrap(ref.key.currency0);
            address token1 = Currency.unwrap(ref.key.currency1);

            // Determine direction
            if (token0 == current.token) {
                otherToken = token1;
                zeroForOne = true;
            } else if (token1 == current.token) {
                otherToken = token0;
                zeroForOne = false;
            } else {
                // pool is not connected to this token (should never happen)
                emit RecoverableInternalError();
                return 0;
            }
        }

        // Build swap simulation
        Swap memory swap = Swap({
            key: ref.key,
            amountIn: uint128(current.output),
            amountOutMin: 1,
            zeroForOne: zeroForOne,
            swapType: ref.swapType
        });

        // Compute output tokens from swap minus gas costs for this swap
        (int256 profit, uint256 output) = getOutTokensOfSwapAfterGas(swap, sellPriceX96, gasPrice);

        if (output == 0)
            return 0;

        Node memory newNode = Node({
            token: otherToken,
            profit: int128(profit),
            output: uint128(output),
            swap: swap,
            previous: bestIndex,  // Is this correct???
            count: current.count + 1
        });

        index = uint32(allNodes.length);

        // Push updated node to open set
        allNodes.push(newNode);
    }

    event RevenueGenerated(uint256 ethEarned, uint256 estimatedTransactionFee, uint256 txFeeRefund);
    event SwapGroupFailed(SwapGroup group);

    function swapManyWithLend(SwapGroup[] calldata groups, uint256 deadline) external returns (uint256 ethEarned) {
        uint256 gasUsed = gasleft();
        if (deadline < block.timestamp)
            return 0;

        ethEarned = 0;

        for (uint16 i = 0; i < groups.length; i++) {
            try poolManager.unlock(abi.encode(0, abi.encode(groups[i]))) returns (bytes memory result) {
                uint256 earned = abi.decode(result, (uint256));
                ethEarned += earned;
            } catch {
                emit SwapGroupFailed(groups[i]);
            }
        }

        gasUsed -= gasleft();
        uint256 txFee = (gasUsed + 25000) * tx.gasprice;

        uint256 refund = 0;
        if (msg.sender == tx.origin) {
            refund = ethEarned > txFee ? txFee : ethEarned;
            if (!payable(tx.origin).send(refund))
                refund = 0;
        }

        emit RevenueGenerated(ethEarned, txFee, refund);

        if (lyEtaPerviyRaz && txFee < ethEarned) {
            emit FirstProfit(ethEarned, ethEarned - txFee);
            lyEtaPerviyRaz = false;
        }
    }

    function _unlockCallback(
        bytes calldata rawData
    ) internal override returns (bytes memory) {
        (uint256 command, bytes memory commandData) = abi.decode(rawData, (uint256, bytes));

        if (command == 0) {
            SwapGroup memory data = abi.decode(commandData, (SwapGroup));

            uint32 i;

            uint128 accumulator = 0;
            for (i = 0; i < data.swaps.length;) {
                if (data.swaps[i].amountIn == 0)
                    data.swaps[i].amountIn = accumulator;
                accumulator = _executeSwap(data.swaps[i]);

                unchecked { i++; }
            }

            // Convert all WETH back to ETH
            uint256 wethBalance = WETH.balanceOf(address(this));
            if (wethBalance > 0)
                WETH.withdraw(wethBalance);

            int256 ethDelta = poolManager.currencyDelta(address(this), ETH);
            if (ethDelta > 0)
                _take(ETH, address(this), uint256(ethDelta));
            else if (ethDelta < 0)
                _settle(ETH, address(this), uint256(-ethDelta));
            int256 ethEarned = int256(wethBalance) + ethDelta;
            require(ethEarned >= 0, "Cannot lose eth");

            for (i = 0; i < data.toTake.length;) {
                Currency currency = Currency.wrap(data.toTake[i]);
                _take(currency, address(this), _getFullCredit(currency));

                unchecked { i++; }
            }

            return abi.encode(uint256(ethEarned));

        } else if (command == 1) {
            Swap memory swap = abi.decode(commandData, (Swap));
            (bool success, uint256 tokensOutActual, uint256 gasUsed) = getOutTokensOfSwap(swap);
            return abi.encode(success, tokensOutActual, gasUsed);

        } else if (command == 2) {
            return _lockedFindSwapRoute(commandData);
        }
    }

    // Designed for human use/debugging purposes
    function getOutTokensOfSwapSimple(Swap memory swap) external returns (bool success, uint256 tokensOutActual, uint256 gasUsed) {
        // This locks the V4 pool manager, so we can lend unlimited tokens inside our dry run.
        return abi.decode(poolManager.unlock(abi.encode(1, abi.encode(swap))), (bool, uint256, uint256));
    }

    // Note that UniswapV4 must be locked for this to work!
    function getOutTokensOfSwap(Swap memory swap) public returns (bool success, uint256 tokensOutActual, uint256 gasUsed) {
        bytes memory data;
        (success, data) = simulate(abi.encodeWithSelector(this._swapTest.selector, swap));

        if (success)
            (tokensOutActual, gasUsed) = abi.decode(data, (uint256, uint256));
    }

    function getOutTokensOfSwapAfterGas(Swap memory swap, uint256 priceX96, uint256 gasPrice) internal returns (int256 equivelentEth, uint256 outAmount) {
        uint256 gasUsed;
        bool success;
        (success, outAmount, gasUsed) = getOutTokensOfSwap(swap);
        if (!success)
            return (0, 0);

        // Convert outAmount to our expected eth gained by selling
        equivelentEth = int256(mulDiv(outAmount, priceX96, 1 << 96));

        // Subtract gas costs
        equivelentEth -= int256(gasPrice * gasUsed);
    }

    function simulate(bytes memory data) internal returns (bool success, bytes memory result) {
        // If the simulated call reverts, then _callThenRevert will *not* revert, so if _callThenRevert "succeeds", it actually indicates reversion in simulation.
        (success, result) = address(this).delegatecall(abi.encodeWithSelector(this._callThenRevert.selector, data));

        success = !success;
    }

    bool transient callThenRevertLock;

    function _callThenRevert(bytes memory data) external {
        callThenRevertLock = true;
        (bool success, bytes memory result) = address(this).delegatecall(data);
        callThenRevertLock = false;

        // This makes this call revert when our callee succeeds, and makes this call succeed when the call reverts.
        if (success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _swapTest(Swap memory swap) external returns (uint256 tokensOutActual, uint256 gasUsed) {
        require(callThenRevertLock, "FOOF");

        gasUsed = gasleft();
        tokensOutActual = _executeSwap(swap);
        gasUsed -= gasleft();
    }

    function _executeSwap(Swap memory swap) internal returns (uint128 tokensOut) {
        uint32 version = swap.swapType & 0x0000FFFF;
        address outputToken = address(0);

        if ((swap.swapType & 0xFFFF0000) == UNISWAP || (swap.swapType & 0xFFFF0000) == SUSHI) {
            if (version == 4) {
                uint256 priceX192 = swap.zeroForOne ? mulDiv(swap.amountOutMin, 1 << 192, swap.amountIn) : mulDiv(swap.amountIn, 1 << 192, swap.amountOutMin);
                uint160 sqrtPriceLimitX96 = uint160(sqrt(priceX192));
                IPoolManager.SwapParams memory params = IPoolManager.SwapParams(swap.zeroForOne, -int128(swap.amountIn), sqrtPriceLimitX96);

                BalanceDelta delta = poolManager.swap(swap.key, params, bytes(""));
                tokensOut = uint128(swap.zeroForOne ? delta.amount1() : delta.amount0());
            } else {
                address poolAdr = address(swap.key.hooks);
                if (version == 3) {
                    callbackPayable = poolAdr;

                    address inputToken = swap.zeroForOne ? IUniswapV3Pool(poolAdr).token0() : IUniswapV3Pool(poolAdr).token1();
                    outputToken = swap.zeroForOne ? IUniswapV3Pool(poolAdr).token1() : IUniswapV3Pool(poolAdr).token0();

                    uint160 sqrtPriceLimitX96 = uint160(sqrt(swap.zeroForOne ? mulDiv(swap.amountOutMin, 1 << 192, swap.amountIn) : mulDiv(swap.amountIn, 1 << 192, swap.amountOutMin)));
                    (int256 a0, int256 a1) = IUniswapV3Pool(poolAdr).swap(address(this), swap.zeroForOne, int128(swap.amountIn), sqrtPriceLimitX96, abi.encode(inputToken, swap.amountIn));

                    tokensOut = uint128(uint256(-(swap.zeroForOne ? a1 : a0)));

                } else if (version == 2) {
                    address inputToken = swap.zeroForOne ? IUniswapV2Pair(poolAdr).token0() : IUniswapV2Pair(poolAdr).token1();
                    outputToken = swap.zeroForOne ? IUniswapV2Pair(poolAdr).token1() : IUniswapV2Pair(poolAdr).token0();

                    // Obtain the input tokens via flash lending
                    if (inputToken == address(WETH)) {
                        _take(ETH, address(this), swap.amountIn);
                        WETH.deposit{value: swap.amountIn}();
                    } else
                        _take(Currency.wrap(inputToken), address(this), swap.amountIn);
                    IERC20(inputToken).transfer(poolAdr, swap.amountIn);

                    (uint112 tokensOut112, uint112 tokensIn,) = IUniswapV2Pair(poolAdr).getReserves();
                    if (swap.zeroForOne)
                        (tokensOut112, tokensIn) = (tokensIn, tokensOut112);
                    uint256 amtOut = UniswapV2Library.getAmountOut(swap.amountIn, tokensIn, tokensOut112);
                    tokensOut = uint128(amtOut);
                    require(amtOut >= swap.amountOutMin, "V2: Not enough received");
                    IUniswapV2Pair(poolAdr).swap(swap.zeroForOne ? 0 : amtOut, swap.zeroForOne ? amtOut : 0, address(this), bytes(""));
                }
            }
        } else if ((swap.swapType & 0xFFFF0000) == PANCAKE) {
            address poolAdr = address(swap.key.hooks);
            if (version == 3) {
                callbackPayable = poolAdr;

                address inputToken = swap.zeroForOne ? IPancakeV3Pool(poolAdr).token0() : IPancakeV3Pool(poolAdr).token1();
                outputToken = swap.zeroForOne ? IPancakeV3Pool(poolAdr).token1() : IPancakeV3Pool(poolAdr).token0();

                uint160 sqrtPriceLimitX96 = uint160(sqrt(swap.zeroForOne ? mulDiv(swap.amountOutMin, 1 << 192, swap.amountIn) : mulDiv(swap.amountIn, 1 << 192, swap.amountOutMin)));
                (int256 a0, int256 a1) = IPancakeV3Pool(poolAdr).swap(address(this), swap.zeroForOne, int128(swap.amountIn), sqrtPriceLimitX96, abi.encode(inputToken, swap.amountIn));

                tokensOut = uint128(uint256(-(swap.zeroForOne ? a1 : a0)));

            } else if (version == 2) {
                address inputToken = swap.zeroForOne ? IPancakeV2Pair(poolAdr).token0() : IPancakeV2Pair(poolAdr).token1();
                outputToken = swap.zeroForOne ? IPancakeV2Pair(poolAdr).token1() : IPancakeV2Pair(poolAdr).token0();

                // Obtain the input tokens via flash lending
                if (inputToken == address(WETH)) {
                    _take(ETH, address(this), swap.amountIn);
                    WETH.deposit{value: swap.amountIn}();
                } else
                    _take(Currency.wrap(inputToken), address(this), swap.amountIn);
                IERC20(inputToken).transfer(poolAdr, swap.amountIn);

                (uint112 tokensOut112, uint112 tokensIn,) = IPancakeV2Pair(poolAdr).getReserves();
                if (swap.zeroForOne)
                    (tokensOut112, tokensIn) = (tokensIn, tokensOut112);
                uint256 amtOut = UniswapV2Library.getAmountOut(swap.amountIn, tokensIn, tokensOut112);
                tokensOut = uint128(amtOut);
                require(amtOut >= swap.amountOutMin, "V2: Not enough received");
                IPancakeV2Pair(poolAdr).swap(swap.zeroForOne ? 0 : amtOut, swap.zeroForOne ? amtOut : 0, address(this), bytes(""));
            }
        }

        // Pay down anything (we may not have lended it yet; pay it anyway)
        if (outputToken != address(WETH) && outputToken != address(0))
            _settle(Currency.wrap(outputToken), address(this), swap.amountOutMin);
    }

    /**
     * @notice Implementation of DeltaResolver's payment method
     * @dev Transfers tokens to the pool manager to settle negative deltas
     * @param token The token to transfer
     * @param amount The amount to transfer
     */
    function _pay(Currency token, address sender, uint256 amount) internal override {
        //revert("\"Oh hon, I'm a southern girl, I don't carry money!\" (inside joke, true story)");
        if (sender == address(this))
            IERC20(Currency.unwrap(token)).transfer(address(poolManager), amount);
        else
            IERC20(Currency.unwrap(token)).transferFrom(sender, address(poolManager), amount);
    }

    fallback() external payable { }
    receive() external payable { }

    address transient callbackPayable;

    function uniswapV3SwapCallback(int256 a, int256 b, bytes calldata _data) public {
        (address token, uint256 amount) = abi.decode(_data, (address, uint256));
        require(callbackPayable == msg.sender);

        if (a > 0 && a < int256(amount))
            amount = uint256(a);
        else if (b > 0 && b < int256(amount))
            amount = uint256(b);

        uint256 balance = token == address(WETH) ? address(this).balance : IERC20(token).balanceOf(address(this));

        if (amount > balance) {
            // Obtain the input tokens via flash lending
            uint256 needed = amount - balance;
            if (token == address(WETH)) {
                _take(ETH, address(this), needed);
                WETH.deposit{value: needed}();
            } else
                _take(Currency.wrap(token), address(this), needed);
        }

        IERC20(token).transfer(callbackPayable, amount);
    }

    function pancakeV3SwapCallback(int256 a, int256 b, bytes calldata _data) external {
        uniswapV3SwapCallback(a, b, _data);
    }

    function rescueTokens(address[] calldata tokens) public {
        address recipient = msg.sender;
        require(feeCollectors[msg.sender], "Not a fee collector");

        // For each specified token, send our whole balance
        for (uint16 i = 0; i < tokens.length;) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).transfer(recipient, balance);

            unchecked { i++; }
        }

        // Send our eth too
        // Even if our balance is empty, this function is called so that if the
        // fee recipient is a smart contract, the logic for that contract will
        // execute even if there is no eth to send (just tokens)
        payable(recipient).transfer(address(this).balance);
    }

    function setCanCollect(address collector, bool canCollect) external onlyOwner {
        feeCollectors[collector] = canCollect;
    }

	// https://ethereum-magicians.org/t/eip-7054-gas-efficient-square-root-calculation-with-binary-search-approach/14539
	function sqrt(uint x) public pure returns (uint128) {
		if (x == 0) return 0;
		else {
			uint xx = x;
			uint r = 1;
			if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
			if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
			if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
			if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
			if (xx >= 0x100) { xx >>= 8; r <<= 4; }
			if (xx >= 0x10) { xx >>= 4; r <<= 2; }
			if (xx >= 0x8) { r <<= 1; }

			unchecked {
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
				r = (r + x / r) >> 1;
			}
			uint r1 = x / r;
			return uint128 (r < r1 ? r : r1);
		}
	}

	// From https://arbiscan.io/contractdiffchecker?a2=0x819356bf26d384e7e70cd26c07fc807e6b354f08&a1=0x48e455852669adb747b3d16f2bd8b541d696b697
	function mulDiv(uint256 a, uint256 b, uint256 denominator) public pure returns (uint256 result) {
		unchecked {
			// 512-bit multiply [prod1 prod0] = a * b
			// Compute the product mod 2**256 and mod 2**256 - 1
			// then use the Chinese Remainder Theorem to reconstruct
			// the 512 bit result. The result is stored in two 256
			// variables such that product = prod1 * 2**256 + prod0
			uint256 prod0; // Least significant 256 bits of the product
			uint256 prod1; // Most significant 256 bits of the product
			assembly {
				let mm := mulmod(a, b, not(0))
				prod0 := mul(a, b)
				prod1 := sub(sub(mm, prod0), lt(mm, prod0))
			}

			// Handle non-overflow cases, 256 by 256 division
			if (prod1 == 0) {
				require(denominator > 0);
				assembly {
					result := div(prod0, denominator)
				}
				return result;
			}

			// Make sure the result is less than 2**256.
			// Also prevents denominator == 0
			require(denominator > prod1);

			///////////////////////////////////////////////
			// 512 by 256 division.
			///////////////////////////////////////////////

			// Make division exact by subtracting the remainder from [prod1 prod0]
			// Compute remainder using mulmod
			uint256 remainder;
			assembly {
				remainder := mulmod(a, b, denominator)
			}
			// Subtract 256 bit number from 512 bit number
			assembly {
				prod1 := sub(prod1, gt(remainder, prod0))
				prod0 := sub(prod0, remainder)
			}

			// Factor powers of two out of denominator
			// Compute largest power of two divisor of denominator.
			// Always >= 1.
			uint256 twos = (0 - denominator) & denominator;
			// Divide denominator by power of two
			assembly {
				denominator := div(denominator, twos)
			}

			// Divide [prod1 prod0] by the factors of two
			assembly {
				prod0 := div(prod0, twos)
			}
			// Shift in bits from prod1 into prod0. For this we need
			// to flip `twos` such that it is 2**256 / twos.
			// If twos is zero, then it becomes one
			assembly {
				twos := add(div(sub(0, twos), twos), 1)
			}
			prod0 |= prod1 * twos;

			// Invert denominator mod 2**256
			// Now that denominator is an odd number, it has an inverse
			// modulo 2**256 such that denominator * inv = 1 mod 2**256.
			// Compute the inverse by starting with a seed that is correct
			// correct for four bits. That is, denominator * inv = 1 mod 2**4
			uint256 inv = (3 * denominator) ^ 2;
			// Now use Newton-Raphson iteration to improve the precision.
			// Thanks to Hensel's lifting lemma, this also works in modular
			// arithmetic, doubling the correct bits in each step.
			inv *= 2 - denominator * inv; // inverse mod 2**8
			inv *= 2 - denominator * inv; // inverse mod 2**16
			inv *= 2 - denominator * inv; // inverse mod 2**32
			inv *= 2 - denominator * inv; // inverse mod 2**64
			inv *= 2 - denominator * inv; // inverse mod 2**128
			inv *= 2 - denominator * inv; // inverse mod 2**256

			// Because the division is now exact we can divide by multiplying
			// with the modular inverse of denominator. This will give us the
			// correct result modulo 2**256. Since the precoditions guarantee
			// that the outcome is less than 2**256, this is the final result.
			// We don't need to compute the high bits of the result and prod1
			// is no longer required.
			result = prod0 * inv;
			return result;
		}
	}
}

