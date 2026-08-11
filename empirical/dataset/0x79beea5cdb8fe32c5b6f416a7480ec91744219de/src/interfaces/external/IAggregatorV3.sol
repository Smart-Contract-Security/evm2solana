// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IAggregatorV3
/// @notice Chainlink AggregatorV3Interface 최소 인터페이스 (NAV 계산에 필요한 함수만 포함)
interface IAggregatorV3 {
    /// @notice 최신 라운드 데이터를 반환
    /// @return roundId 라운드 ID
    /// @return answer 가격 (feedDecimals 소수점)
    /// @return startedAt 라운드 시작 시각
    /// @return updatedAt 가격 업데이트 시각
    /// @return answeredInRound 응답이 확정된 라운드 ID
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice 피드 소수점 자릿수 반환
    function decimals() external view returns (uint8);
}
