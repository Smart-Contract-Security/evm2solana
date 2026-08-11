// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VaultInitParams} from "./VaultTypes.sol";

/// @title IVault
/// @notice Factory가 Vault를 초기화하고 시드 예치를 수행하기 위한 인터페이스
interface IVault {
    /// @notice Vault를 초기화한다 (BeaconProxy 배포 직후 Factory가 1회 호출)
    /// @param params Vault 초기화 파라미터
    function initialize(VaultInitParams calldata params) external;

    /// @notice 시드 예치를 실행한다 (Factory가 createVault 내부에서 호출)
    /// @param seedAmount 시드 USDT 금액
    /// @param minSharesOut 최소 수령 Share 수 (슬리피지 보호)
    /// @param maxSlippageBps 자산 매수 시 허용 최대 슬리피지 (bps, MAX_USER_SLIPPAGE_BPS 이하)
    /// @return sharesOut 발행된 Share 수량
    function executeSeedDeposit(uint256 seedAmount, uint256 minSharesOut, uint256 maxSlippageBps)
        external
        returns (uint256 sharesOut);

    /// @notice Vault 를 일시정지한다 (DEFAULT_ADMIN_ROLE 만, factory 가 wrapper 로 호출)
    function pause() external;

    /// @notice Vault 일시정지를 해제한다 (DEFAULT_ADMIN_ROLE 만)
    function unpause() external;
}
