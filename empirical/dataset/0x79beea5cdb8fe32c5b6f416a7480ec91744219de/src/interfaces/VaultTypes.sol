// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Vault 리밸런싱 주기 정책
enum RebalancePolicy {
    MANUAL, // 0: 생성자만, 언제든 가능
    MONTHLY, // 1: 30일 주기
    QUARTERLY, // 2: 90일 주기
    SEMI_ANNUAL // 3: 180일 주기
}

/// @notice 화이트리스트 자산 설정 정보
struct AssetConfig {
    address token;
    address priceFeed; // Chainlink AggregatorV3Interface 주소
    uint8 tokenDecimals;
    uint8 feedDecimals;
    uint24 uniswapFeeTier; // 500, 3000, 10000
    bool hasFeeOnTransfer;
    bool enabled;
    // === 신규 (CONS-06) ===
    /// @notice Chainlink staleness 한도 (초). 자산별 heartbeat에 맞춰 설정.
    ///         예: BTC/USD 1h heartbeat → 3600, XAU/USD 24h heartbeat → 90000(25h+여유).
    ///         0은 등록 시점에 InvalidMaxPriceAge로 거부됨.
    uint32 maxPriceAge;
}

/// @notice Vault 초기화 파라미터 (Factory → Vault.initialize 전달용)
struct VaultInitParams {
    string name;
    string symbol;
    string description;
    address[] assets;
    uint16[] targetWeightsBps;
    RebalancePolicy rebalancePolicy;
    uint256 initialSharePrice;
    address creator;
    uint16 feeBps;
}
