// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ISwapRouter
/// @notice Uniswap V3 SwapRouter02 최소 인터페이스 (exactInputSingle 함수만 포함)
/// @dev SwapRouter02 (v2)는 deadline을 파라미터가 아닌 multicall 래퍼로 처리.
///      Vault 코드에서 deadline은 deposit/redeem/rebalance 함수 레벨에서 이미 체크하므로
///      스왑 호출 시점에는 별도 deadline이 필요하지 않음.
interface ISwapRouter {
    /// @notice exactInputSingle 스왑 파라미터 (SwapRouter02 기준)
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice 단일 풀에서 정확한 입력량으로 스왑 수행
    /// @param params 스왑 파라미터
    /// @return amountOut 수령한 출력 토큰 수량
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
