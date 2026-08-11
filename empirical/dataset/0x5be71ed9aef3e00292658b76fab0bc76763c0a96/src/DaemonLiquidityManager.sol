// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/* -----------------------------------------------------------------------
 *                       DAEMONS Liquidity Manager
 * -----------------------------------------------------------------------
 * Owner-controlled bootstrap position manager for the ETH / DAEMON
 * Uniswap v4 pool.
 *
 * Website: https://daemons.life
 * Twitter: https://x.com/DAEMONSv4
 *
 * @title DAEMONS Liquidity Manager
 * @author DAEMONSv4
 * @notice Creates the DAEMON pool and holds the initial full-range liquidity.
 * -------------------------------------------------------------------- */

import "./ChainConfig.sol";
import "./DaemonToken.sol";

struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

interface IERC20Minimal {
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IPoolManagerMinimal {
    function unlock(bytes calldata data) external returns (bytes memory);
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);
    function sync(Currency currency) external;
    function take(Currency currency, address to, uint256 amount) external;
    function settle() external payable returns (uint256 paid);
}

contract DaemonLiquidityManager {
    enum Action {
        AddLiquidity,
        RemoveLiquidity
    }

    IPoolManagerMinimal public immutable MANAGER;

    address public owner;
    bool public poolCreated;
    PoolKey public poolKey;
    int256 public liquidityPosition;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PoolCreated(bytes32 indexed poolId, uint160 sqrtPriceX96, int24 tick);
    event LiquidityAdded(address indexed owner, int256 liquidityDelta, int128 amount0, int128 amount1);
    event LiquidityRemoved(address indexed owner, int256 liquidityDelta, int128 amount0, int128 amount1);

    error OwnerOnly();
    error ZeroAddress();
    error PoolAlreadyCreated();
    error PoolNotCreated();
    error InvalidLiquidity();
    error InvalidPool();
    error TransferFailed();
    error NativeTransferFailed();
    error ManagerOnly();

    constructor(address initialOwner) {
        MANAGER = IPoolManagerMinimal(ChainConfig.poolManager(block.chainid));
        if (initialOwner == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    receive() external payable {}

    modifier onlyOwner() {
        if (msg.sender != owner) revert OwnerOnly();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function createPoolAndAddLiquidity(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int256 liquidityDelta,
        uint256 maxTokenIn
    ) external payable onlyOwner returns (BalanceDelta delta) {
        if (poolCreated) revert PoolAlreadyCreated();
        if (liquidityDelta <= 0) revert InvalidLiquidity();
        if (!_hasNativeAndToken(key)) revert InvalidPool();

        address token = _tokenCurrency(key);
        _pullToken(token, msg.sender, maxTokenIn);

        poolKey = key;
        poolCreated = true;

        int24 tick = MANAGER.initialize(key, sqrtPriceX96);
        emit PoolCreated(_poolId(key), sqrtPriceX96, tick);

        delta = _modifyLiquidity(Action.AddLiquidity, msg.sender, key, liquidityDelta);
        liquidityPosition += liquidityDelta;

        _refundToken(token, msg.sender);
        _refundNative(msg.sender);
    }

    function withdrawLiquidity(int256 liquidityDelta) external onlyOwner returns (BalanceDelta delta) {
        if (!poolCreated) revert PoolNotCreated();
        if (liquidityPosition <= 0) revert InvalidLiquidity();

        if (liquidityDelta == 0) {
            liquidityDelta = liquidityPosition;
        }
        if (liquidityDelta <= 0 || liquidityDelta > liquidityPosition) revert InvalidLiquidity();

        delta = _modifyLiquidity(Action.RemoveLiquidity, msg.sender, poolKey, -liquidityDelta);
        liquidityPosition -= liquidityDelta;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory result) {
        if (msg.sender != address(MANAGER)) revert ManagerOnly();

        (Action action, address recipient, PoolKey memory key, int256 liquidityDelta) =
            abi.decode(data, (Action, address, PoolKey, int256));

        (BalanceDelta delta,) = MANAGER.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -887220, tickUpper: 887220, liquidityDelta: liquidityDelta, salt: bytes32(0)
            }),
            ""
        );

        _settleOrTake(key.currency0, recipient, _amount0(delta));
        _settleOrTake(key.currency1, recipient, _amount1(delta));

        if (action == Action.AddLiquidity) {
            emit LiquidityAdded(recipient, liquidityDelta, _amount0(delta), _amount1(delta));
        } else {
            emit LiquidityRemoved(recipient, -liquidityDelta, _amount0(delta), _amount1(delta));
        }

        return abi.encode(delta);
    }

    function _modifyLiquidity(Action action, address recipient, PoolKey memory key, int256 liquidityDelta)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(MANAGER.unlock(abi.encode(action, recipient, key, liquidityDelta)), (BalanceDelta));
    }

    function _settleOrTake(Currency currency, address recipient, int128 amount) internal {
        if (amount < 0) {
            uint256 owed = _abs(amount);
            if (Currency.unwrap(currency) == address(0)) {
                MANAGER.settle{value: owed}();
            } else {
                MANAGER.sync(currency);
                _transferToken(Currency.unwrap(currency), address(MANAGER), owed);
                MANAGER.settle();
            }
        } else if (amount > 0) {
            MANAGER.take(currency, recipient, uint256(uint128(amount)));
        }
    }

    function _pullToken(address token, address from, uint256 amount) internal {
        if (amount == 0) return;
        bool ok = IERC20Minimal(token).transferFrom(from, address(this), amount);
        if (!ok) revert TransferFailed();
    }

    function _transferToken(address token, address to, uint256 amount) internal {
        bool ok = IERC20Minimal(token).transfer(to, amount);
        if (!ok) revert TransferFailed();
    }

    function _refundToken(address token, address to) internal {
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        if (balance != 0) _transferToken(token, to, balance);
    }

    function _refundNative(address to) internal {
        uint256 balance = address(this).balance;
        if (balance != 0) {
            (bool ok,) = payable(to).call{value: balance}("");
            if (!ok) revert NativeTransferFailed();
        }
    }

    function _hasNativeAndToken(PoolKey calldata key) internal pure returns (bool) {
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        return
            (currency0 == address(0) && currency1 != address(0)) || (currency1 == address(0) && currency0 != address(0));
    }

    function _tokenCurrency(PoolKey calldata key) internal pure returns (address) {
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        return currency0 == address(0) ? currency1 : currency0;
    }

    function _poolId(PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks));
    }

    function _amount0(BalanceDelta delta) internal pure returns (int128 amount) {
        int256 raw = BalanceDelta.unwrap(delta);
        assembly ("memory-safe") {
            amount := sar(128, raw)
        }
    }

    function _amount1(BalanceDelta delta) internal pure returns (int128 amount) {
        int256 raw = BalanceDelta.unwrap(delta);
        assembly ("memory-safe") {
            amount := signextend(15, raw)
        }
    }

    function _abs(int128 value) internal pure returns (uint256) {
        int256 signed = int256(value);
        unchecked {
            return uint256(signed >= 0 ? signed : -signed);
        }
    }
}
