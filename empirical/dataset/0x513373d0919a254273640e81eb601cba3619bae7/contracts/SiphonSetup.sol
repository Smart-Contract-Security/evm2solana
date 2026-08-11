// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {Siphon} from "./Siphon.sol";
import {SiphonHook} from "./SiphonHook.sol";

/// @title SiphonSetup
/// @notice One contract to launch SIPHON safely:
///   • deploys Siphon + SiphonHook (CREATE2 with mined salt)
///   • initializes the canonical V4 pool (gated to this contract by the hook)
///   • adds the entire SIPHON supply + ETH as a single full-range LP position
///   • holds the LP position; owner can later remove it
///   • flips `tradingEnabled` on the hook
///
/// All three "frontrunable" actions (pool init, initial LP, first swap) are
/// gated on the hook to `setupContract == this`. A bot cannot anchor the pool
/// at a bad price or seed adversarial liquidity ahead of the owner.
contract SiphonSetup is IUnlockCallback {
    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    /// @dev Default pool fee/tickSpacing. Fee = 0 because the hook already taxes 10%.
    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 60;

    address public immutable owner;
    IPoolManager public immutable poolManager;

    Siphon public siphon;
    SiphonHook public hook;
    PoolKey public poolKey;
    bool public poolInitialized;
    bool public liquidityAdded;

    int24 public lpTickLower;
    int24 public lpTickUpper;
    uint128 public lpLiquidity;

    enum Action { Add, Remove }

    event ContractsDeployed(address siphon, address hook);
    event PoolInitialized(uint160 sqrtPriceX96);
    event LiquidityAdded(uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint128 liquidity, address recipient);

    error NotOwner();
    error NotPoolManager();
    error AlreadyDeployed();
    error NotDeployed();
    error AlreadySetup();
    error NoEth();
    error HookFlagsMismatch();
    error HookDeployFailed();
    error InvalidLiquidity();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IPoolManager _poolManager, address _owner) {
        poolManager = _poolManager;
        owner = _owner;
    }

    // ─────────────────────────── STEP 1: DEPLOY ───────────────────────────

    /// @notice Deploys Siphon (mints 1M to this contract) and SiphonHook at the
    ///         mined address. The hook salt must be mined off-chain such that
    ///         `(hookAddr & 0x3FFF) == HOOK_FLAGS`; otherwise this reverts.
    function deployAll(bytes32 hookSalt) external onlyOwner returns (address, address) {
        if (address(siphon) != address(0)) revert AlreadyDeployed();

        siphon = new Siphon(address(this));

        bytes memory initCode = abi.encodePacked(
            type(SiphonHook).creationCode,
            abi.encode(poolManager, address(siphon), address(this))
        );
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), hookSalt)
        }
        if (deployed == address(0)) revert HookDeployFailed();
        if (uint160(deployed) & 0x3FFF != HOOK_FLAGS) revert HookFlagsMismatch();

        hook = SiphonHook(deployed);
        siphon.setHook(deployed);
        siphon.excludeFromReflections(address(poolManager));

        emit ContractsDeployed(address(siphon), deployed);
        return (address(siphon), deployed);
    }

    // ───────────────────── STEP 2: INIT POOL + ADD LP ─────────────────────

    /// @notice Initializes the canonical SIPHON pool, then atomically adds 100%
    ///         of the SIPHON supply held here + `msg.value` ETH as full-range LP.
    /// @dev    `enableTrading()` is intentionally NOT called here so the owner
    ///         can verify the LP add succeeded before opening trading.
    function setupPool(uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper)
        external
        payable
        onlyOwner
    {
        if (address(siphon) == address(0)) revert NotDeployed();
        if (poolInitialized) revert AlreadySetup();
        if (msg.value == 0) revert NoEth();

        // ETH is always currency0 since address(0) is the smallest possible address.
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(siphon)),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        poolManager.initialize(poolKey, sqrtPriceX96);
        poolInitialized = true;
        emit PoolInitialized(sqrtPriceX96);

        uint256 siphonAmount = siphon.balanceOf(address(this));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            msg.value,
            siphonAmount
        );
        if (liquidity == 0) revert InvalidLiquidity();

        lpTickLower = tickLower;
        lpTickUpper = tickUpper;
        lpLiquidity = liquidity;
        liquidityAdded = true;

        poolManager.unlock(abi.encode(Action.Add, int256(uint256(liquidity)), tickLower, tickUpper, address(0)));

        emit LiquidityAdded(liquidity, msg.value, siphonAmount);
    }

    // ─────────────────────── STEP 3: ENABLE TRADING ───────────────────────

    function enableTrading() external onlyOwner {
        hook.enableTrading();
    }

    // ─────────────────────────── REMOVE LP ───────────────────────────────

    /// @notice Remove some/all of the LP position. Owner-only.
    function removeLiquidity(uint128 liquidityToRemove, address payable recipient)
        external
        onlyOwner
    {
        if (liquidityToRemove == 0 || liquidityToRemove > lpLiquidity) revert InvalidLiquidity();

        unchecked { lpLiquidity -= liquidityToRemove; }

        poolManager.unlock(
            abi.encode(Action.Remove, -int256(uint256(liquidityToRemove)), lpTickLower, lpTickUpper, recipient)
        );

        emit LiquidityRemoved(liquidityToRemove, recipient);
    }

    // ─────────────────────── V4 UNLOCK CALLBACK ──────────────────────────

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();

        (Action action, int256 liquidityDelta, int24 tickLower, int24 tickUpper, address recipient) =
            abi.decode(data, (Action, int256, int24, int24, address));

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        (BalanceDelta delta,) = poolManager.modifyLiquidity(poolKey, params, "");

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Settle currency0 (ETH).
        if (amount0 < 0) {
            // Owe ETH to the pool.
            poolManager.settle{value: uint256(uint128(-amount0))}();
        } else if (amount0 > 0) {
            // Pull ETH out.
            address payable to = action == Action.Remove ? payable(recipient) : payable(address(this));
            poolManager.take(poolKey.currency0, to, uint256(uint128(amount0)));
        }

        // Settle currency1 (SIPHON).
        if (amount1 < 0) {
            uint256 owed = uint256(uint128(-amount1));
            poolManager.sync(poolKey.currency1);
            siphon.transfer(address(poolManager), owed);
            poolManager.settle();
        } else if (amount1 > 0) {
            address to = action == Action.Remove ? recipient : address(this);
            poolManager.take(poolKey.currency1, to, uint256(uint128(amount1)));
        }

        return "";
    }

    receive() external payable {}
}
