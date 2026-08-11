// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {AssetConfig, VaultInitParams, RebalancePolicy} from "../interfaces/VaultTypes.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IAggregatorV3} from "../interfaces/external/IAggregatorV3.sol";

/// @title VaultFactory
/// @notice Vault 생성(Beacon Proxy 배포), 자산 화이트리스트 관리, 업그레이드를 담당하는 팩토리 컨트랙트
/// @dev UUPS Upgradeable + AccessControlEnumerableUpgradeable 사용
///      DEFAULT_ADMIN_ROLE: Owner (업그레이드, treasury 변경)
///      OPERATOR_ROLE: Operator (자산 관리, 긴급 정지, KEEPER 관리)
///      KEEPER_ROLE:   비-creator rebalance 자동화 봇 (OPERATOR 가 admin)
contract VaultFactory is Initializable, AccessControlEnumerableUpgradeable, UUPSUpgradeable, IVaultFactory {
    using SafeERC20 for IERC20;

    // =========================================================================
    // 역할 상수
    // =========================================================================

    /// @notice 운영자 역할 — 자산 화이트리스트 관리 및 긴급 정지 권한
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice rebalance keeper 역할 (V4 신규) — Vault.rebalance() 비-creator 경로 호출 권한.
    /// @dev V3 까지의 `_keepers` mapping 은 V4 에서 deprecated. KEEPER_ROLE 의 admin 은 OPERATOR_ROLE 로
    ///      설정 (initializeV4) — OPERATOR 가 grantRole/revokeRole 또는 wrapper(`addKeeper`/`removeKeeper`) 로 관리.
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // =========================================================================
    // 커스텀 에러
    // =========================================================================

    /// @notice 전역 일시정지 상태에서 vault 생성 시도
    error GlobalPausedError();
    /// @notice 실제 피드 소수점과 입력값 불일치 시
    error InvalidFeedDecimals(uint8 actual, uint8 expected);
    /// @notice 이미 등록된 자산을 다시 등록 시도
    error AssetAlreadyRegistered(address token);
    /// @notice 등록되지 않은 자산에 접근 시도
    error AssetNotRegistered(address token);
    /// @notice 비활성화된 자산을 Vault 생성에 포함 시도
    error AssetNotEnabled(address token);
    /// @notice 목표 비중 합계가 10000 bps가 아닐 때
    error InvalidWeightSum(uint16 sum);
    /// @notice 자산 목록에 중복이 있을 때
    error DuplicateAsset(address token);
    /// @notice 자산 개수가 최대(10개) 초과 시
    error TooManyAssets(uint256 count);
    /// @notice 자산 개수가 최소(1개) 미만 시
    error TooFewAssets();
    /// @notice 시드 금액이 최소값 미만일 때
    error SeedBelowMinimum(uint256 provided, uint256 minimum);
    /// @notice deadline이 이미 경과했을 때
    error DeadlineExpired(uint256 deadline, uint256 current);
    /// @notice 잘못된 주소(zero address) 전달 시
    error ZeroAddress();
    /// @notice maxPriceAge가 0으로 전달 시
    error InvalidMaxPriceAge();
    /// @notice assets 배열과 weights 배열 길이 불일치 시
    error LengthMismatch(uint256 assetsLen, uint256 weightsLen);
    /// @notice keeper 주소가 zero일 때 (CONS-03)
    error InvalidKeeper();
    /// @notice V3 reinitializer 입력 검증 실패 (CONS-03)
    error InvalidV3Params();
    /// @notice V4 backfill 입력에 chain 상태와 불일치하는 EOA 가 포함됨
    /// @dev caller 가 existingOwners/Operators/Keepers 를 잘못 추출했을 때 발생.
    ///      backfill 은 정합성 보장이 핵심이라 mismatch 시 실패가 안전.
    error V4BackfillMismatch();

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice 새 Vault가 생성되었을 때 발행
    event VaultCreated(
        address indexed vault,
        address indexed creator,
        address[] assets,
        uint16[] weights,
        uint8 rebalancePolicy,
        uint256 seedAmount,
        uint256 seedShares
    );

    /// @notice 자산이 화이트리스트에 등록/변경되었을 때 발행
    event AssetWhitelisted(address indexed token, bool enabled);

    /// @notice 자산이 화이트리스트에 신규 등록되었을 때 발행 (maxPriceAge, fee tier 포함)
    event AssetAdded(address indexed token, address indexed priceFeed, uint24 uniswapFeeTier, uint32 maxPriceAge);

    /// @notice 자산 설정이 업데이트되었을 때 발행
    event AssetConfigUpdated(address indexed token);

    /// @notice 전역 일시정지가 활성화되었을 때 발행
    event GlobalPaused(address indexed by);

    /// @notice 전역 일시정지가 해제되었을 때 발행
    event GlobalUnpaused(address indexed by);

    /// @notice 플랫폼 treasury 주소가 변경되었을 때 발행
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice keeper allowlist가 변경되었을 때 발행 (CONS-03)
    event KeeperUpdated(address indexed keeper, bool allowed);

    /// @notice 최소 시드 금액이 변경되었을 때 발행
    event MinSeedAmountUpdated(uint256 oldAmount, uint256 newAmount);

    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice Vault 구현체를 관리하는 Beacon
    UpgradeableBeacon public beacon;

    /// @notice 플랫폼 수수료 수령 주소
    address public override platformTreasury;

    /// @notice USDT 토큰 주소
    address public override usdt;

    /// @notice Uniswap V3 스왑 라우터 주소
    address public override swapRouter;

    /// @notice 기본 수수료율 (bps, 예: 15 = 0.15%)
    uint16 public defaultFeeBps;

    /// @notice Vault 생성 시 필요한 최소 시드 금액 (USDT 단위)
    uint256 public minSeedAmount;

    /// @notice 전역 일시정지 상태
    bool public override globalPaused;

    /// @notice 배포된 모든 Vault 주소 목록
    address[] public allVaults;

    /// @notice 배포된 Vault 총 개수
    uint256 public vaultCount;

    /// @notice 토큰 주소 → 자산 설정 매핑
    mapping(address => AssetConfig) private _assets;

    /// @notice 화이트리스트 자산 주소 목록
    address[] public assetList;

    /// @notice 화이트리스트 자산 개수
    uint256 public assetCount;

    /// @dev V3 에서 도입된 keeper allowlist mapping. V4 부터 KEEPER_ROLE (OZ AccessControlEnumerable
    ///      `_roleMembers`) 로 대체되어 사용하지 않는다. UUPS storage layout 호환성을 위해 slot 만 보존.
    ///      메인넷 fresh deploy 시점에 함께 제거 + 테스트넷 리셋 예정 (단일 형상 유지).
    /// slither-disable-next-line unused-state
    mapping(address => bool) private __deprecated_keepers;

    /// @dev 업그레이드 가능한 컨트랙트의 스토리지 레이아웃 충돌 방지용 갭
    /// @notice V4 에서 추가 storage 없음 (AccessControlEnumerable 은 ERC-7201 namespace 격리).
    uint256[49] private __gap;

    // =========================================================================
    // 초기화
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 팩토리를 초기화한다
    /// @param owner DEFAULT_ADMIN_ROLE을 부여받을 주소
    /// @param operator OPERATOR_ROLE을 부여받을 주소
    /// @param treasury 플랫폼 수수료 수령 주소
    /// @param _usdt USDT 토큰 주소
    /// @param _swapRouter Uniswap V3 스왑 라우터 주소
    /// @param _beacon UpgradeableBeacon 주소
    /// @param _defaultFeeBps 기본 수수료율 (bps)
    /// @param _minSeedAmount 최소 시드 금액 (USDT 단위)
    function initialize(
        address owner,
        address operator,
        address treasury,
        address _usdt,
        address _swapRouter,
        address _beacon,
        uint16 _defaultFeeBps,
        uint256 _minSeedAmount
    ) external initializer {
        if (owner == address(0)) revert ZeroAddress();
        if (operator == address(0)) revert ZeroAddress();
        if (treasury == address(0)) revert ZeroAddress();
        if (_usdt == address(0)) revert ZeroAddress();
        if (_swapRouter == address(0)) revert ZeroAddress();
        if (_beacon == address(0)) revert ZeroAddress();

        __AccessControl_init();
        // Note: OZ v5에서 __UUPSUpgradeable_init()은 제거됨 (초기화 불필요)

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(OPERATOR_ROLE, operator);

        // V4: KEEPER_ROLE 의 admin = OPERATOR_ROLE (OPERATOR 가 grantRole/revokeRole 가능).
        // 메인넷 fresh deploy 시 그대로 적용, 테스트넷 V4 업그레이드는 initializeV4 에서도 동일 호출.
        _setRoleAdmin(KEEPER_ROLE, OPERATOR_ROLE);

        beacon = UpgradeableBeacon(_beacon);
        platformTreasury = treasury;
        usdt = _usdt;
        swapRouter = _swapRouter;
        defaultFeeBps = _defaultFeeBps;
        minSeedAmount = _minSeedAmount;
    }

    // =========================================================================
    // Vault 생성
    // =========================================================================

    /// @notice 새 Vault를 생성하고 시드 예치를 atomic하게 수행한다
    /// @dev 호출 전 msg.sender는 USDT.approve(VaultFactory, seedAmount)를 완료해야 함
    /// @param name ERC-20 name
    /// @param symbol ERC-20 symbol
    /// @param description Vault 설명 (온체인 저장)
    /// @param assets 기초자산 주소 배열 (1~10개)
    /// @param targetWeightsBps 목표 비중 배열 (합계 = 10000 bps)
    /// @param rebalancePolicy 리밸런싱 정책
    /// @param initialSharePrice 최초 Share 가격 (기본 1e18 = $1)
    /// @param seedAmount 시드 예치 USDT 금액 (>= minSeedAmount)
    /// @param minSharesOut 시드 예치 시 수령할 최소 Share 수 (슬리피지 보호)
    /// @param deadline 트랜잭션 유효 기한
    /// @param maxSlippageBps 시드 자산 매수 시 허용 최대 슬리피지 (bps, Vault.MAX_USER_SLIPPAGE_BPS 이하)
    /// @return vault 배포된 Vault 컨트랙트 주소
    function createVault(
        string calldata name,
        string calldata symbol,
        string calldata description,
        address[] calldata assets,
        uint16[] calldata targetWeightsBps,
        RebalancePolicy rebalancePolicy,
        uint256 initialSharePrice,
        uint256 seedAmount,
        uint256 minSharesOut,
        uint256 deadline,
        uint256 maxSlippageBps
    ) external returns (address vault) {
        // 전역 일시정지 확인
        if (globalPaused) revert GlobalPausedError();

        // deadline 확인
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);

        // 시드 금액 확인
        if (seedAmount < minSeedAmount) revert SeedBelowMinimum(seedAmount, minSeedAmount);

        // 입력 검증
        _validateCreateVaultInputs(assets, targetWeightsBps);

        // BeaconProxy 배포
        vault = address(new BeaconProxy(address(beacon), ""));

        // Vault 초기화
        VaultInitParams memory params = VaultInitParams({
            name: name,
            symbol: symbol,
            description: description,
            assets: assets,
            targetWeightsBps: targetWeightsBps,
            rebalancePolicy: rebalancePolicy,
            initialSharePrice: initialSharePrice,
            creator: msg.sender,
            feeBps: defaultFeeBps
        });

        IVault(vault).initialize(params);

        // 생성자로부터 시드 USDT를 Factory로 전송 후 Vault에 위임
        IERC20(usdt).safeTransferFrom(msg.sender, vault, seedAmount);

        // 시드 예치 실행 (수수료 면제, 목표 비중 기준 매수). maxSlippageBps 검증은 Vault에서.
        uint256 sharesOut = IVault(vault).executeSeedDeposit(seedAmount, minSharesOut, maxSlippageBps);

        // Vault 목록 등록
        allVaults.push(vault);
        unchecked {
            ++vaultCount;
        }

        emit VaultCreated(vault, msg.sender, assets, targetWeightsBps, uint8(rebalancePolicy), seedAmount, sharesOut);
    }

    // =========================================================================
    // 자산 화이트리스트 관리 (OPERATOR_ROLE)
    // =========================================================================

    /// @notice 새 자산을 화이트리스트에 등록한다
    /// @param token 등록할 토큰 주소
    /// @param priceFeed Chainlink 가격 피드 주소
    /// @param tokenDecimals 토큰 소수점
    /// @param feedDecimals 가격 피드 소수점
    /// @param uniswapFeeTier Uniswap V3 fee tier (500, 3000, 10000)
    /// @param hasFeeOnTransfer 전송 수수료 발생 여부 (PAXG 등)
    /// @param maxPriceAge Chainlink staleness 한도 (초). 자산별 heartbeat에 맞춰 설정 (CONS-06).
    ///                   예: BTC/USD 1h heartbeat → 3600, XAU/USD 24h heartbeat → 90000(25h+여유).
    function addAsset(
        address token,
        address priceFeed,
        uint8 tokenDecimals,
        uint8 feedDecimals,
        uint24 uniswapFeeTier,
        bool hasFeeOnTransfer,
        uint32 maxPriceAge
    ) external onlyRole(OPERATOR_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (priceFeed == address(0)) revert ZeroAddress();
        if (maxPriceAge == 0) revert InvalidMaxPriceAge();
        if (_assets[token].token != address(0)) revert AssetAlreadyRegistered(token);

        // 실제 피드 소수점과 입력값 일치 검증
        uint8 actualDecimals = IAggregatorV3(priceFeed).decimals();
        if (actualDecimals != feedDecimals) revert InvalidFeedDecimals(actualDecimals, feedDecimals);

        _assets[token] = AssetConfig({
            token: token,
            priceFeed: priceFeed,
            tokenDecimals: tokenDecimals,
            feedDecimals: feedDecimals,
            uniswapFeeTier: uniswapFeeTier,
            hasFeeOnTransfer: hasFeeOnTransfer,
            enabled: true,
            maxPriceAge: maxPriceAge
        });

        assetList.push(token);
        unchecked {
            ++assetCount;
        }

        emit AssetWhitelisted(token, true);
        emit AssetAdded(token, priceFeed, uniswapFeeTier, maxPriceAge);
    }

    /// @notice 자산을 비활성화한다 (기존 Vault에는 영향 없음)
    /// @param token 비활성화할 토큰 주소
    function removeAsset(address token) external onlyRole(OPERATOR_ROLE) {
        if (_assets[token].token == address(0)) revert AssetNotRegistered(token);

        _assets[token].enabled = false;

        emit AssetWhitelisted(token, false);
    }

    /// @notice 자산 설정을 업데이트한다
    /// @param token 업데이트할 토큰 주소
    /// @param config 새 설정값
    /// @dev WARNING: 변경 즉시 모든 기존 Vault에 영향 (NAV, 슬리피지 계산 등)
    ///      TODO [메인넷]: 타임락 또는 2단계 커밋 패턴 적용 권장
    function updateAssetConfig(address token, AssetConfig calldata config) external onlyRole(OPERATOR_ROLE) {
        if (_assets[token].token == address(0)) revert AssetNotRegistered(token);
        if (config.token != token) revert AssetNotRegistered(token);

        _assets[token] = config;

        emit AssetConfigUpdated(token);
    }

    /// @notice V2 업그레이드 마이그레이션 — 기존 자산의 maxPriceAge를 일괄 채움 (CONS-06)
    /// @dev `reinitializer(2)`로 영구 1회만 실행. UUPS `upgradeToAndCall`로 atomic upgrade+migration.
    ///      외부에 영구 setter 노출 없음. 향후 maxPriceAge 변경이 필요하면 새 implementation의
    ///      `reinitializer(3)` 함수를 가진 별도 upgrade로 처리 (CONS-04 동결 정신과 일관).
    ///      `onlyRole(DEFAULT_ADMIN_ROLE)`로 race condition 차단 (upgrade caller가 admin이라 통과).
    /// @param tokens 마이그레이션할 토큰 주소 배열
    /// @param maxPriceAges 각 토큰의 새 staleness 한도 (초). 0 거부.
    function initializeV2(address[] calldata tokens, uint32[] calldata maxPriceAges)
        external
        reinitializer(2)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (tokens.length != maxPriceAges.length) {
            revert LengthMismatch(tokens.length, maxPriceAges.length);
        }
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len;) {
            if (_assets[tokens[i]].token == address(0)) revert AssetNotRegistered(tokens[i]);
            if (maxPriceAges[i] == 0) revert InvalidMaxPriceAge();
            _assets[tokens[i]].maxPriceAge = maxPriceAges[i];
            emit AssetConfigUpdated(tokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    // =========================================================================
    // 전역 일시정지 (OPERATOR_ROLE)
    // =========================================================================

    /// @notice 전역 일시정지를 활성화한다 — 모든 Vault의 deposit이 차단됨
    function globalPause() external onlyRole(OPERATOR_ROLE) {
        globalPaused = true;
        emit GlobalPaused(msg.sender);
    }

    /// @notice 전역 일시정지를 해제한다
    function globalUnpause() external onlyRole(OPERATOR_ROLE) {
        globalPaused = false;
        emit GlobalUnpaused(msg.sender);
    }

    // =========================================================================
    // 개별 Vault 일시정지 (V5 — OPERATOR_ROLE wrapper)
    // =========================================================================

    /// @notice 특정 Vault 를 일시정지한다 — OPERATOR 가 vault.pause() 를 직접 호출할 수 없으므로
    ///         factory 가 wrapper 로 호출한다. factory 는 모든 vault 의 DEFAULT_ADMIN_ROLE 보유.
    /// @dev V5 신규. 이전엔 backend 가 vault.pause() 를 OPERATOR PK 로 직접 호출하던 dead code.
    function pauseVault(address vault) external onlyRole(OPERATOR_ROLE) {
        IVault(vault).pause();
    }

    /// @notice 특정 Vault 일시정지를 해제한다 — OPERATOR 만 가능 (V5 신규).
    function unpauseVault(address vault) external onlyRole(OPERATOR_ROLE) {
        IVault(vault).unpause();
    }

    // =========================================================================
    // Keeper allowlist (CONS-03, OPERATOR_ROLE)
    // =========================================================================

    /// @notice keeper 주소를 allowlist 에 추가한다 — Vault.rebalance() 비-creator 경로 호출 권한 부여.
    /// @dev V4: OZ KEEPER_ROLE 로 위임. `_grantRole` 이 already granted 이면 false 반환 — 그때만
    ///      KeeperUpdated 도 skip (idempotent). 권한 체크는 grantRole 의 admin role(=OPERATOR_ROLE)
    ///      이 자동 처리 — modifier `onlyRole(OPERATOR_ROLE)` 명시는 중복.
    function addKeeper(address keeper) external onlyRole(OPERATOR_ROLE) {
        if (keeper == address(0)) revert InvalidKeeper();
        if (_grantRole(KEEPER_ROLE, keeper)) {
            emit KeeperUpdated(keeper, true);
        }
    }

    /// @notice keeper 주소를 allowlist 에서 제거한다.
    function removeKeeper(address keeper) external onlyRole(OPERATOR_ROLE) {
        if (_revokeRole(KEEPER_ROLE, keeper)) {
            emit KeeperUpdated(keeper, false);
        }
    }

    /// @notice 주어진 주소가 keeper allowlist 에 등록되어 있는지 반환 (IVaultFactory).
    /// @dev V4 부터 KEEPER_ROLE 보유 여부와 동치.
    function isKeeper(address account) external view override returns (bool) {
        return hasRole(KEEPER_ROLE, account);
    }

    /// @notice 현재 등록된 모든 keeper EOA 목록을 반환한다 (V4 신규).
    /// @dev OZ AccessControlEnumerable `getRoleMembers` 위임. backend chain-roles 가 events 인덱싱
    ///      대신 본 view 를 직접 호출 — 진실의 원천 = chain.
    function getKeepers() external view returns (address[] memory) {
        return getRoleMembers(KEEPER_ROLE);
    }

    // =========================================================================
    // V3 마이그레이션 (CONS-02 / 03 / 07 / Donation 보호)
    // =========================================================================

    /// @notice V3 업그레이드 마이그레이션 — keeper allowlist 초기화 + minSeedAmount 상향.
    /// @dev `reinitializer(3)`로 영구 1회만 실행. UUPS `upgradeToAndCall`로 atomic upgrade+migration.
    ///      외부에 영구 setter 노출 없음. 추후 minSeedAmount 변경이 필요하면 `setMinSeedAmount`를 통해 처리.
    /// @param newMinSeedAmount 새 최소 시드 금액 (USDT 6dec). mainnet-checklist 권고치 5,000 USDT.
    /// @param initialKeepers V3 직후 등록할 keeper 주소 배열 (빈 배열 허용 — 이후 addKeeper로 추가).
    function initializeV3(uint256 newMinSeedAmount, address[] calldata initialKeepers)
        external
        reinitializer(3)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newMinSeedAmount == 0) revert InvalidV3Params();

        uint256 oldAmount = minSeedAmount;
        minSeedAmount = newMinSeedAmount;
        emit MinSeedAmountUpdated(oldAmount, newMinSeedAmount);

        uint256 len = initialKeepers.length;
        for (uint256 i = 0; i < len;) {
            address k = initialKeepers[i];
            if (k == address(0)) revert InvalidKeeper();
            // V3 의 _keepers mapping (V4부터 deprecated, slot 보존용) + V4 KEEPER_ROLE 동시 set.
            // sepolia 의 V3 reinitializer 는 이미 호출 완료라 본 path 는 fresh deploy 시에만 발동.
            __deprecated_keepers[k] = true;
            _grantRole(KEEPER_ROLE, k);
            emit KeeperUpdated(k, true);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice V4 업그레이드 마이그레이션 — KEEPER_ROLE 도입 + 기존 보유자(OWNER/OPERATOR/V3 keepers)를
    ///         AccessControlEnumerable `_roleMembers` enum set 에 backfill.
    /// @dev `reinitializer(4)` 로 영구 1회. UUPS `upgradeToAndCall` 로 atomic upgrade+migration.
    ///
    ///   왜 backfill 이 필요한가:
    ///     V3 까지 부모는 `AccessControlUpgradeable` — `_roles` mapping 만 사용.
    ///     V4 부모 `AccessControlEnumerableUpgradeable` 는 namespace `_roleMembers` (EnumerableSet) 추가.
    ///     V3 시점에 grant 된 보유자는 `_roleMembers` 에 등록 안 되어 있어 `getRoleMembers` 결과가 비게 된다.
    ///     OZ `_grantRole` 은 already granted 이면 early return — 단순 재호출로는 enum 에 추가 안 됨.
    ///     → revoke→grant 사이클로 enum 동기화 (atomic, 외부 노출 0).
    ///
    ///   KEEPER 는 새 role 이라 hasRole=false → 단순 grantRole 만으로 enum 등록.
    ///
    /// @param existingOwners      V3 시점 DEFAULT_ADMIN_ROLE 보유자 전부
    /// @param existingOperators   V3 시점 OPERATOR_ROLE      보유자 전부
    /// @param existingKeepers     V3 시점 _keepers mapping=true 인 EOA 전부
    function initializeV4(
        address[] calldata existingOwners,
        address[] calldata existingOperators,
        address[] calldata existingKeepers
    ) external reinitializer(4) onlyRole(DEFAULT_ADMIN_ROLE) {
        // (1) KEEPER_ROLE 의 admin 설정 — initialize 에서 하지 못한 V3-from-V4 path.
        _setRoleAdmin(KEEPER_ROLE, OPERATOR_ROLE);

        // (2) DEFAULT_ADMIN_ROLE / OPERATOR_ROLE 의 기존 보유자 → enum 동기화 (revoke+grant)
        uint256 len = existingOwners.length;
        for (uint256 i = 0; i < len;) {
            address a = existingOwners[i];
            if (!hasRole(DEFAULT_ADMIN_ROLE, a)) revert V4BackfillMismatch();
            _revokeRole(DEFAULT_ADMIN_ROLE, a);
            _grantRole(DEFAULT_ADMIN_ROLE, a);
            unchecked { ++i; }
        }
        len = existingOperators.length;
        for (uint256 i = 0; i < len;) {
            address a = existingOperators[i];
            if (!hasRole(OPERATOR_ROLE, a)) revert V4BackfillMismatch();
            _revokeRole(OPERATOR_ROLE, a);
            _grantRole(OPERATOR_ROLE, a);
            unchecked { ++i; }
        }

        // (3) V3 keepers (_deprecated mapping) → KEEPER_ROLE 으로 이전, mapping 정리.
        len = existingKeepers.length;
        for (uint256 i = 0; i < len;) {
            address k = existingKeepers[i];
            if (!__deprecated_keepers[k]) revert V4BackfillMismatch();
            __deprecated_keepers[k] = false; // mapping 정리 (V4 부터 사용 안 함)
            _grantRole(KEEPER_ROLE, k);
            // KeeperUpdated 는 V4 wrapper 와 호환 — 여기서는 grantRole 의 RoleGranted 만 emit.
            // 외부 인덱서가 KeeperUpdated 의존 시 backfill 결과를 별도 path 로 인지하도록 함.
            unchecked { ++i; }
        }
    }

    /// @notice 최소 시드 금액을 변경한다 (DEFAULT_ADMIN_ROLE).
    function setMinSeedAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAmount == 0) revert InvalidV3Params();
        uint256 oldAmount = minSeedAmount;
        minSeedAmount = newAmount;
        emit MinSeedAmountUpdated(oldAmount, newAmount);
    }

    // =========================================================================
    // 관리자 기능 (DEFAULT_ADMIN_ROLE)
    // =========================================================================

    /// @notice Vault 구현체를 업그레이드한다 (Beacon 업그레이드 → 모든 Vault에 즉시 적용)
    /// @param newImpl 새 Vault 구현체 주소
    function upgradeVaultImplementation(address newImpl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImpl == address(0)) revert ZeroAddress();
        beacon.upgradeTo(newImpl);
    }

    /// @notice 플랫폼 treasury 주소를 변경한다
    /// @param newTreasury 새 treasury 주소
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    // =========================================================================
    // 조회 함수 (IVaultFactory 구현)
    // =========================================================================

    /// @notice 특정 토큰의 자산 설정 정보를 반환
    function getAssetConfig(address token) external view override returns (AssetConfig memory) {
        return _assets[token];
    }

    /// @notice 특정 토큰이 활성화된 화이트리스트 자산인지 확인
    function isAssetEnabled(address token) external view override returns (bool) {
        return _assets[token].enabled;
    }

    // =========================================================================
    // 추가 조회 함수
    // =========================================================================

    /// @notice 화이트리스트 자산 주소 전체 목록을 반환
    function getAssetList() external view returns (address[] memory) {
        return assetList;
    }

    /// @notice 화이트리스트 자산 개수를 반환
    function getAssetCount() external view returns (uint256) {
        return assetCount;
    }

    /// @notice 배포된 모든 Vault 주소 목록을 반환
    /// @dev WARNING: allVaults 배열이 커지면 가스 한도 초과 가능.
    ///      프로덕션에서는 인덱서(Backend)에서 DB 조회를 사용하고, 이 함수는 소규모 조회용.
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /// @notice 배포된 Vault 총 개수를 반환
    function getVaultCount() external view returns (uint256) {
        return vaultCount;
    }

    // =========================================================================
    // 내부 함수
    // =========================================================================

    /// @notice createVault 입력값을 검증한다
    function _validateCreateVaultInputs(address[] calldata assets, uint16[] calldata targetWeightsBps) internal view {
        uint256 len = assets.length;

        if (len == 0) revert TooFewAssets();
        if (len > 10) revert TooManyAssets(len);
        if (len != targetWeightsBps.length) revert LengthMismatch(len, targetWeightsBps.length);

        // 비중 합계 검증 및 중복·비활성화 자산 확인
        uint256 weightSum;
        for (uint256 i = 0; i < len;) {
            address asset = assets[i];

            // Base asset(USDT)는 whitelist 없이 허용 — 현금 보관 자산으로 사용
            if (asset != usdt) {
                AssetConfig storage config = _assets[asset];
                if (config.token == address(0)) revert AssetNotRegistered(asset);
                if (!config.enabled) revert AssetNotEnabled(asset);
            }

            // 중복 확인
            for (uint256 j = 0; j < i;) {
                if (assets[j] == asset) revert DuplicateAsset(asset);
                unchecked {
                    ++j;
                }
            }

            weightSum += targetWeightsBps[i];

            unchecked {
                ++i;
            }
        }

        if (weightSum != 10000) revert InvalidWeightSum(uint16(weightSum));
    }

    /// @notice UUPS 업그레이드 권한 검증 — DEFAULT_ADMIN_ROLE만 가능
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
