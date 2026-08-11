// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AssetConfig} from "./VaultTypes.sol";

/// @title IVaultFactory
/// @notice Vault 컨트랙트가 Factory로부터 조회하는 인터페이스
interface IVaultFactory {
    /// @notice 특정 토큰의 자산 설정 정보를 반환
    /// @param token 조회할 토큰 주소
    function getAssetConfig(address token) external view returns (AssetConfig memory);

    /// @notice 특정 토큰이 활성화된 화이트리스트 자산인지 확인
    /// @param token 확인할 토큰 주소
    function isAssetEnabled(address token) external view returns (bool);

    /// @notice 전역 일시정지 상태 반환
    function globalPaused() external view returns (bool);

    /// @notice 플랫폼 수수료 수령 주소 반환
    function platformTreasury() external view returns (address);

    /// @notice Uniswap V3 스왑 라우터 주소 반환
    function swapRouter() external view returns (address);

    /// @notice USDT 토큰 주소 반환
    function usdt() external view returns (address);

    /// @notice 주어진 주소가 keeper allowlist에 등록되어 있는지 반환 (CONS-03)
    /// @param account 조회할 주소
    function isKeeper(address account) external view returns (bool);
}
