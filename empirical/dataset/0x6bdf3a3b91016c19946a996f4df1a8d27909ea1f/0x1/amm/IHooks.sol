// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHooks {
    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
    }

    function getHookPermissions() external view returns (Permissions memory);

    function beforeInitialize(address sender, bytes32 poolId, uint256 startPrice) external returns (bytes4);
    function afterInitialize(address sender, bytes32 poolId, uint256 startPrice) external returns (bytes4);

    function beforeAddLiquidity(address sender, bytes32 poolId, uint256 amount0, uint256 amount1) external returns (bytes4);
    function afterAddLiquidity(address sender, bytes32 poolId, uint256 amount0, uint256 amount1) external returns (bytes4);

    function beforeRemoveLiquidity(address sender, bytes32 poolId, uint256 liquidity) external returns (bytes4);
    function afterRemoveLiquidity(address sender, bytes32 poolId, uint256 liquidity) external returns (bytes4);

    /// @notice Called before swap math. A non-zero `feeOverrideBps` replaces the pool's
    ///         default LP fee for this swap (hard-capped at 5_000).
    function beforeSwap(
        address sender,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn
    ) external returns (bytes4 selector, uint16 feeOverrideBps);

    function afterSwap(
        address sender,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (bytes4);
}
