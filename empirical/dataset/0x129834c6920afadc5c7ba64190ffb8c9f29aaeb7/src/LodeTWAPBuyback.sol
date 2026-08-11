// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  LodeTWAPBuyback
/// @notice Time-weighted-average-price buyback for LODE token.
///         Owner deposits ETH and configures a plan: total amount + number of
///         slices + interval. Anyone can call execute() to trigger the next
///         slice when due. Each slice swaps a fixed amount of ETH for LODE via
///         the v4 pool and sends the LODE directly to the burn address.
///
///         Permissionless execution means the buyback continues even if the
///         owner is offline. Owner can pause or withdraw remaining ETH at any
///         time.
contract LodeTWAPBuyback is IUnlockCallback {
    using CurrencyLibrary for Currency;

    error NotOwner();
    error NotPoolManager();
    error NoPlan();
    error PlanPaused();
    error PlanComplete();
    error SliceNotDue();
    error InsufficientBalance();
    error InvalidPlan();
    error SwapFailed();

    event PlanConfigured(
        uint256 totalAmount,
        uint256 numSlices,
        uint256 intervalSeconds,
        uint256 startTime
    );
    event PlanPausedSet(bool paused);
    event SliceExecuted(uint256 indexed sliceIndex, uint256 ethSpent, uint256 lodeBurned);
    event Withdrawn(address indexed to, uint256 amount);

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint160 internal constant MIN_SQRT_PRICE = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970341;

    address public owner;
    IPoolManager public immutable poolManager;
    PoolKey public poolKey;

    struct Plan {
        uint256 totalAmount;
        uint256 numSlices;
        uint256 intervalSeconds;
        uint256 startTime;
        uint256 slicesExecuted;
        bool paused;
    }

    Plan public plan;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        PoolKey memory _poolKey,
        address _owner
    ) {
        poolManager = _poolManager;
        poolKey = _poolKey;
        owner = _owner;
    }

    receive() external payable {}

    /// @notice Configure a new plan. Resets slicesExecuted to zero. Can only
    ///         reconfigure if the current plan is complete or paused.
    function configurePlan(
        uint256 _totalAmount,
        uint256 _numSlices,
        uint256 _intervalSeconds,
        uint256 _startTime
    ) external onlyOwner {
        if (_totalAmount == 0 || _numSlices == 0 || _intervalSeconds == 0) revert InvalidPlan();
        if (_startTime < block.timestamp) _startTime = block.timestamp;
        if (
            plan.numSlices != 0 &&
            plan.slicesExecuted < plan.numSlices &&
            !plan.paused
        ) revert InvalidPlan();

        plan = Plan({
            totalAmount: _totalAmount,
            numSlices: _numSlices,
            intervalSeconds: _intervalSeconds,
            startTime: _startTime,
            slicesExecuted: 0,
            paused: false
        });

        emit PlanConfigured(_totalAmount, _numSlices, _intervalSeconds, _startTime);
    }

    /// @notice Pause or resume the active plan.
    function setPaused(bool _paused) external onlyOwner {
        plan.paused = _paused;
        emit PlanPausedSet(_paused);
    }

    /// @notice Anyone can call this to execute the next slice if due.
    function execute() external {
        if (plan.numSlices == 0) revert NoPlan();
        if (plan.paused) revert PlanPaused();
        if (plan.slicesExecuted >= plan.numSlices) revert PlanComplete();

        uint256 nextSliceTime = plan.startTime + plan.slicesExecuted * plan.intervalSeconds;
        if (block.timestamp < nextSliceTime) revert SliceNotDue();

        uint256 sliceAmount = plan.totalAmount / plan.numSlices;
        if (address(this).balance < sliceAmount) revert InsufficientBalance();

        bytes memory result = poolManager.unlock(abi.encode(sliceAmount));
        uint256 lodeBurned = abi.decode(result, (uint256));

        plan.slicesExecuted += 1;
        emit SliceExecuted(plan.slicesExecuted, sliceAmount, lodeBurned);
    }

    /// @notice Callback from PoolManager to execute the swap.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        uint256 sliceAmount = abi.decode(data, (uint256));

        // For a LODE/ETH pool with currency0 = ETH:
        // We swap ETH (currency0) for LODE (currency1) → zeroForOne = true
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(0);
        uint160 priceLimit = zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1;

        BalanceDelta delta = poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(sliceAmount),
                sqrtPriceLimitX96: priceLimit
            }),
            ""
        );

        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();

        // Settle ETH side (we owe currency0)
        if (a0 < 0) {
            uint256 owe = uint256(uint128(-a0));
            poolManager.sync(poolKey.currency0);
            poolManager.settle{value: owe}();
        }

        // Take LODE side and send directly to burn
        uint256 lodeBurned = 0;
        if (a1 > 0) {
            lodeBurned = uint256(uint128(a1));
            poolManager.take(poolKey.currency1, BURN_ADDRESS, lodeBurned);
        }

        return abi.encode(lodeBurned);
    }

    /// @notice Owner can withdraw any remaining ETH. Useful for plan
    ///         cancellation or post-plan cleanup.
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool ok, ) = owner.call{value: bal}("");
        if (!ok) revert SwapFailed();
        emit Withdrawn(owner, bal);
    }

    /// @notice Transfer ownership to a new address.
    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    // --- views ---

    function nextSliceTime() external view returns (uint256) {
        if (plan.numSlices == 0 || plan.slicesExecuted >= plan.numSlices) return 0;
        return plan.startTime + plan.slicesExecuted * plan.intervalSeconds;
    }

    function sliceAmount() external view returns (uint256) {
        if (plan.numSlices == 0) return 0;
        return plan.totalAmount / plan.numSlices;
    }

    function isReady() external view returns (bool) {
        if (plan.numSlices == 0 || plan.paused) return false;
        if (plan.slicesExecuted >= plan.numSlices) return false;
        uint256 due = plan.startTime + plan.slicesExecuted * plan.intervalSeconds;
        if (block.timestamp < due) return false;
        uint256 amount = plan.totalAmount / plan.numSlices;
        return address(this).balance >= amount;
    }
}
