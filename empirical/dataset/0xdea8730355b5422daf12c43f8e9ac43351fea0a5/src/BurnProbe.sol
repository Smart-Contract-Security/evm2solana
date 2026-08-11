// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/src/auth/Ownable.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {Rescuable} from "./utils/Rescuable.sol";

/// @title BurnProbe
/// @notice Throwaway mainnet probe for SeasonSloplingsController's
///         ETH -> SLOP -> DEAD swap path. The `unlockCallback` body is a
///         deliberate verbatim copy of
///         `SeasonSloplingsController.unlockCallback`
///         (contracts/src/seasons/SeasonSloplingsController.sol:318-346) so what
///         this contract exercises against the real V4 pool is the same code
///         path that will run inside `requestOpen` in production. Delete after
///         the live test.
contract BurnProbe is IUnlockCallback, Ownable, Rescuable {
    using BalanceDeltaLibrary for BalanceDelta;

    error NotPoolManager();
    error UnexpectedDeltaSign();
    error NothingToBurn();
    error ZeroOwner();

    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    IPoolManager public immutable poolManager;
    PoolKey public poolKey;

    uint256 public totalEthBurned;
    uint256 public totalSlopBurned;
    uint256 public burnCount;

    event SlopBurned(address indexed from, uint256 ethIn, uint256 slopBurned);

    constructor(address owner_, IPoolManager poolManager_, PoolKey memory poolKey_) {
        require(owner_ != address(0), ZeroOwner());
        _initializeOwner(owner_);
        poolManager = poolManager_;
        poolKey = poolKey_;
    }

    /// @notice Swap `msg.value` ETH -> SLOP through `poolKey`, forward SLOP to
    ///         DEAD, return the SLOP burned. Permissionless: anyone may call.
    function burn() external payable returns (uint256 slopBurned) {
        require(msg.value > 0, NothingToBurn());
        bytes memory ret = poolManager.unlock(abi.encode(msg.value));
        slopBurned = abi.decode(ret, (uint256));
        totalEthBurned += msg.value;
        totalSlopBurned += slopBurned;
        unchecked { burnCount++; }
        emit SlopBurned(msg.sender, msg.value, slopBurned);
    }

    /// @inheritdoc IUnlockCallback
    /// @dev Verbatim copy of SeasonSloplingsController.unlockCallback
    ///      (contracts/src/seasons/SeasonSloplingsController.sol:318-346).
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), NotPoolManager());
        uint256 ethIn = abi.decode(data, (uint256));

        PoolKey memory key = poolKey;
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        int128 a0 = delta.amount0();
        int128 a1 = delta.amount1();
        require(a0 < 0 && a1 > 0, UnexpectedDeltaSign());

        uint256 ethOwed = uint256(int256(-a0));
        uint256 slopOut = uint256(int256(a1));

        // Sync currency0 (native ETH) before settling; see PoolManager `_settle`.
        poolManager.sync(key.currency0);
        poolManager.settle{value: ethOwed}();
        poolManager.take(key.currency1, DEAD, slopOut);

        return abi.encode(slopOut);
    }

    function _authorizeRescue() internal view override {
        _checkOwner();
    }
}
