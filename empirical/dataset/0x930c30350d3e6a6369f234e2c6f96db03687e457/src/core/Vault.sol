// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AssetConfig, VaultInitParams, RebalancePolicy} from "../interfaces/VaultTypes.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IAggregatorV3} from "../interfaces/external/IAggregatorV3.sol";
import {ISwapRouter} from "../interfaces/external/ISwapRouter.sol";

/// @title Vault
/// @notice ERC-4626 기반 다중 자산 투자 Vault. BeaconProxy 패턴으로 배포된다.
/// @dev 각 Vault는 Factory가 정의한 화이트리스트 자산으로 구성되며, USDT를 기본 결제 자산으로 사용한다.
///      수수료는 구매 시 0.15%만 부과하며 플랫폼 50% / 생성자 50%로 분배된다.
contract Vault is
    Initializable,
    ERC4626Upgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    AccessControlUpgradeable,
    IVault
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // =========================================================================
    // 상수
    // =========================================================================

    /// @notice 생성자 역할 — 수동 리밸런싱 및 수수료 수취 권한
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    /// @notice 수수료율 분모 (10000 bps = 100%)
    uint16 public constant FEE_DENOMINATOR = 10000;

    /// @notice NAV 계산 정밀도 (18 decimals)
    uint256 public constant PRECISION = 1e18;

    /// @notice 사용자가 deposit 시 입력 가능한 최대 슬리피지 (bps, 2%)
    uint256 public constant MAX_USER_SLIPPAGE_BPS = 200;

    /// @notice 비-creator(keeper)의 rebalance 슬리피지 hardcap (bps, 1%)
    uint256 public constant NON_CREATOR_REBALANCE_HARDCAP_BPS = 100;

    /// @notice redeem leg별 oracle 기반 minOut 슬리피지 (bps, 2%) — CONS-07
    uint256 public constant PER_LEG_SLIPPAGE_BPS = 200;

    /// @notice 시드 예치(executeSeedDeposit) 호출 시 Factory가 사용하는 default slippage (bps).
    ///         Factory가 명시하지 않은 경로 보호용 — 일반 호출은 maxSlippageBps 인자를 명시.
    uint16 public constant SEED_DEPOSIT_DEFAULT_SLIPPAGE_BPS = 50;

    /// @notice ERC4626 virtual shares offset — donation/inflation 공격 1차 보호
    uint8 private constant _DECIMALS_OFFSET = 6;

    // =========================================================================
    // 커스텀 에러
    // =========================================================================

    /// @notice 허용 슬리피지 초과 시
    error SlippageExceeded(uint256 received, uint256 minimum);
    /// @notice deadline이 이미 경과했을 때
    error DeadlineExpired(uint256 deadline, uint256 current);
    /// @notice 일시정지 상태에서 deposit 시도 시
    error VaultPaused();
    /// @notice 잘못된 지분 수량 (0 또는 초과) 시
    error InvalidShareAmount();
    /// @notice Chainlink 가격이 staleness 한계를 초과했을 때
    error StalePrice(address token);
    /// @notice Chainlink 가격이 0 이하일 때
    error InvalidPrice(address token);
    /// @notice 리밸런싱 주기가 미충족될 때
    error RebalanceTooEarly(uint256 nextAllowedAt, uint256 current);
    /// @notice 출력 토큰이 USDT/USDC가 아닐 때
    error InvalidOutputToken(address token);
    /// @notice Factory 전용 함수를 외부에서 호출 시
    error OnlyFactory();
    /// @notice 잘못된 초기화 파라미터 전달 시
    error InvalidInitParams();
    /// @notice 인출할 수수료가 없을 때
    error NoFeeToWithdraw();
    /// @notice 잘못된 주소(zero address) 전달 시
    error ZeroAddress();
    /// @notice 예치 금액이 0일 때
    error InvalidDepositAmount();
    /// @notice ERC-4626 표준 함수가 비활성화되었을 때 (커스텀 함수 사용 필요)
    error ERC4626Disabled();
    /// @notice 슬리피지 파라미터가 범위를 초과할 때
    error InvalidSlippage();
    /// @notice MANUAL policy vault에서 비-creator가 rebalance 호출 시
    error OnlyCreatorForManualPolicy();
    /// @notice keeper allowlist에 등록되지 않은 EOA가 rebalance 호출 시
    error KeeperNotAllowed(address caller);
    /// @notice CONS-09: supplyBefore>0 인데 navBefore==0 인 비정상 상태에서 deposit 차단.
    ///         자산 가격 폭락 또는 totalPendingFees>=NAV 잠식으로 NAV가 0으로 clamp 된 경우 발생.
    ///         fallback path 의 initialSharePrice 기준 신규 share 발행 시 기존 holder dilution 우려 → revert.
    error NavCollapse();

    // =========================================================================
    // 이벤트
    // =========================================================================

    /// @notice USDT 예치가 완료되었을 때 발행
    event Deposited(address indexed user, uint256 usdtIn, uint256 sharesOut, uint256 feeAmount);

    /// @notice 환매가 완료되었을 때 발행
    event Redeemed(address indexed user, uint256 sharesIn, address indexed outToken, uint256 outAmount);

    /// @notice 리밸런싱이 완료되었을 때 발행
    event Rebalanced(address indexed triggeredBy, uint16[] beforeWeights, uint16[] afterWeights, uint256 timestamp);

    /// @notice 수수료가 발생했을 때 발행
    event FeeCollected(address indexed payer, uint256 platformAmount, uint256 creatorAmount);

    /// @notice 수수료가 출금되었을 때 발행
    event FeeWithdrawn(address indexed beneficiary, uint256 amount);

    // =========================================================================
    // 상태 변수
    // =========================================================================

    /// @notice Vault 설명 (온체인 저장, 불변)
    string public description;

    /// @notice Vault 생성자 주소 (불변)
    address public creator;

    /// @notice 수수료율 (bps, 불변 — 생성 시 기록)
    uint16 public feeBps;

    /// @notice 리밸런싱 정책 (불변)
    RebalancePolicy public rebalancePolicy;

    /// @notice 최초 Share 가격 (불변, 시드 예치 기준)
    uint256 public initialSharePrice;

    /// @notice 기초자산 주소 배열 (불변)
    address[] private _vaultAssets;

    /// @notice 목표 비중 배열 (bps, 불변)
    uint16[] private _targetWeightsBps;

    /// @notice 마지막 리밸런싱 시각
    uint256 public lastRebalancedAt;

    /// @notice 누적 미출금 수수료 (beneficiary → USDT 금액)
    mapping(address => uint256) public accumulatedFees;

    /// @notice 미출금 수수료 총액 (treasury 주소 변경에도 정확한 NAV 계산을 위해 별도 관리)
    uint256 public totalPendingFees;

    /// @notice Factory 컨트랙트 주소
    IVaultFactory public factory;

    /// @dev 업그레이드 가능한 컨트랙트의 스토리지 레이아웃 충돌 방지용 갭
    uint256[50] private __gap;

    // =========================================================================
    // 초기화
    // =========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Vault를 초기화한다 — Factory가 BeaconProxy 배포 직후 1회만 호출
    /// @param params 초기화 파라미터
    function initialize(VaultInitParams calldata params) external override initializer {
        if (params.assets.length == 0) revert InvalidInitParams();
        if (params.assets.length != params.targetWeightsBps.length) revert InvalidInitParams();
        if (params.creator == address(0)) revert InvalidInitParams();

        __ERC20_init(params.name, params.symbol);
        __ERC4626_init(IERC20(IVaultFactory(msg.sender).usdt()));
        __Pausable_init();
        __AccessControl_init();
        // ReentrancyGuard 초기화 — OZ v5의 non-upgradeable ReentrancyGuard는
        // namespaced storage (slot 0x9b779b17...)를 사용함.
        // constructor에서만 초기화하므로 BeaconProxy에서는 수동 초기화 필요.
        // OZ v5에서 ReentrancyGuardUpgradeable은 제거되어 이 방식이 유일한 방법.
        // _status = NOT_ENTERED(1)로 설정.
        // ⚠ OZ major 업그레이드 시 이 slot 주소가 변경될 수 있으므로 확인 필요.
        assembly {
            sstore(0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00, 1)
        }

        // Factory를 DEFAULT_ADMIN_ROLE로 설정 (Vault는 Factory에 의해 관리)
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CREATOR_ROLE, params.creator);

        factory = IVaultFactory(msg.sender);
        description = params.description;
        creator = params.creator;
        feeBps = params.feeBps;
        rebalancePolicy = params.rebalancePolicy;
        // initialSharePrice 범위 검증: 0이면 기본값($1 = 1e18), 극단값 방지
        uint256 _isp = params.initialSharePrice == 0 ? PRECISION : params.initialSharePrice;
        require(_isp >= 1e15 && _isp <= 1e21, "Invalid initialSharePrice"); // $0.001 ~ $1000
        initialSharePrice = _isp;
        lastRebalancedAt = block.timestamp;

        // 자산 및 비중 저장 (불변)
        uint256 len = params.assets.length;
        for (uint256 i = 0; i < len;) {
            _vaultAssets.push(params.assets[i]);
            _targetWeightsBps.push(params.targetWeightsBps[i]);
            unchecked {
                ++i;
            }
        }
    }

    // =========================================================================
    // 시드 예치 (Factory 전용)
    // =========================================================================

    /// @notice 시드 예치를 실행한다 — Factory의 createVault에서만 호출 가능
    /// @dev USDT는 이미 Factory에서 이 컨트랙트로 전송된 상태여야 함
    /// @dev paused/globalPaused 체크는 Factory.createVault()에서 수행하므로 여기서는 생략
    /// @param seedAmount 시드 USDT 금액
    /// @param minSharesOut 최소 수령 Share 수
    /// @param maxSlippageBps 자산 매수 시 허용 최대 슬리피지 (bps, MAX_USER_SLIPPAGE_BPS 이하)
    /// @return sharesOut 발행된 Share 수량
    function executeSeedDeposit(uint256 seedAmount, uint256 minSharesOut, uint256 maxSlippageBps)
        external
        override
        nonReentrant
        returns (uint256 sharesOut)
    {
        if (msg.sender != address(factory)) revert OnlyFactory();
        if (maxSlippageBps > MAX_USER_SLIPPAGE_BPS) revert InvalidSlippage();

        // 시드 예치는 목표 비중 기준으로 자산 매수 (수수료 면제)
        uint256 deployedValue = _buyAssetsAtTargetWeights(seedAmount, maxSlippageBps);

        // 최초 Share 가격 기준으로 지분 발행
        // sharesOut = deployedValue * PRECISION / initialSharePrice
        sharesOut = deployedValue.mulDiv(PRECISION, initialSharePrice, Math.Rounding.Floor);

        if (sharesOut < minSharesOut) revert SlippageExceeded(sharesOut, minSharesOut);

        // creator에게 Share 발행
        _mint(creator, sharesOut);
    }

    // =========================================================================
    // 예치 (Deposit)
    // =========================================================================

    /// @notice USDT를 예치하고 Share를 수령한다
    /// @param usdtAmount 예치할 USDT 금액
    /// @param receiver Share를 수령할 주소
    /// @param minSharesOut 수령할 최소 Share 수 (슬리피지 보호)
    /// @param deadline 트랜잭션 유효 기한
    /// @param maxSlippageBps 자산 매수 시 허용 최대 슬리피지 (bps, MAX_USER_SLIPPAGE_BPS 이하)
    /// @return sharesOut 발행된 Share 수량
    function deposit(
        uint256 usdtAmount,
        address receiver,
        uint256 minSharesOut,
        uint256 deadline,
        uint256 maxSlippageBps
    ) external nonReentrant returns (uint256 sharesOut) {
        if (usdtAmount == 0) revert InvalidDepositAmount();
        if (receiver == address(0)) revert ZeroAddress();
        if (maxSlippageBps > MAX_USER_SLIPPAGE_BPS) revert InvalidSlippage();
        // 일시정지 상태 확인
        if (paused() || factory.globalPaused()) revert VaultPaused();
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);

        address usdtAddr = asset();

        // USDT 전송 전에 캡처 (전송 후 totalAssets()에 USDT가 포함되어 비중/NAV가 왜곡되므로)
        uint256 supplyBefore = totalSupply();
        uint256 navBefore = totalAssets();
        uint16[] memory weightsBefore = getCurrentWeights();

        // USDT를 Vault로 전송
        IERC20(usdtAddr).safeTransferFrom(msg.sender, address(this), usdtAmount);

        // 수수료 차감 (0.15%)
        uint256 feeAmount = usdtAmount.mulDiv(feeBps, FEE_DENOMINATOR, Math.Rounding.Floor);
        uint256 netAmount = usdtAmount - feeAmount;

        // 수수료 분배 (플랫폼 50% / 생성자 50%)
        uint256 platformFee = feeAmount / 2;
        uint256 creatorFee = feeAmount - platformFee;

        address treasury = factory.platformTreasury();
        accumulatedFees[treasury] += platformFee;
        accumulatedFees[creator] += creatorFee;
        totalPendingFees += feeAmount;

        emit FeeCollected(msg.sender, platformFee, creatorFee);

        // USDT 전송 전 캡처한 비중으로 자산 매수
        // CONS-02-A: _swapUSDTForAsset이 valueInUsdt = amountIn 기준으로 가산하므로
        //            deployedValue ≈ netAmount (스왑 손실은 vault 전체 NAV에 균등 흡수, deposit user에게만 몰리지 않음)
        uint256 deployedValue = _buyAssetsWithWeights(netAmount, weightsBefore, maxSlippageBps);

        // Share 발행: 스왑 전 NAV 기준
        // CONS-09: supplyBefore>0 && navBefore==0 는 비정상 상태(가격 폭락 또는 totalPendingFees>=NAV).
        //         fallback path 진입 시 신규 사용자에게 initialSharePrice 기준 무한 share 발행 →
        //         기존 holder dilution. 차단하여 운영자 globalPause + 조사 유도.
        if (supplyBefore == 0) {
            sharesOut = deployedValue.mulDiv(PRECISION, initialSharePrice, Math.Rounding.Floor);
        } else if (navBefore == 0) {
            revert NavCollapse();
        } else {
            sharesOut = deployedValue.mulDiv(supplyBefore, navBefore, Math.Rounding.Floor);
        }

        if (sharesOut < minSharesOut) revert SlippageExceeded(sharesOut, minSharesOut);

        _mint(receiver, sharesOut);

        emit Deposited(msg.sender, usdtAmount, sharesOut, feeAmount);
    }

    // =========================================================================
    // 환매 (Redeem)
    // =========================================================================

    /// @notice Share를 소각하고 USDT를 수령한다.
    /// @dev V6: paused/globalPaused 상태에서 redeem 차단 — deposit/rebalance 와 일관.
    ///      이전 V5 까지는 "긴급 탈출" 명분으로 paused 시에도 허용했으나, oracle/swap 비정상 환경에서
    ///      먼저 환매한 사용자가 과대평가된 share 로 자산을 가져가 남은 사용자에게 손실이 전가되는
    ///      bank run 위험이 있어 폐기. 진정한 긴급 회수는 향후 별도 emergencyWithdraw 경로로 제공 예정.
    /// @param shares 소각할 Share 수량
    /// @param receiver 출력 토큰을 수령할 주소
    /// @param owner Share 소유자 주소
    /// @param minOut 수령할 최소 USDT 금액 (슬리피지 보호)
    /// @param deadline 트랜잭션 유효 기한
    /// @return outAmount 수령한 USDT 금액
    function redeem(uint256 shares, address receiver, address owner, uint256 minOut, uint256 deadline)
        external
        nonReentrant
        returns (uint256 outAmount)
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (shares == 0) revert InvalidShareAmount();
        if (paused() || factory.globalPaused()) revert VaultPaused();
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (shares > balanceOf(owner)) revert InvalidShareAmount();

        // owner가 msg.sender가 아니면 allowance 확인
        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        outAmount = _redeemShares(shares, owner, receiver, asset(), minOut);

        emit Redeemed(msg.sender, shares, asset(), outAmount);
    }

    /// @notice Share를 소각하고 USDT 또는 USDC를 수령한다 (출력 토큰 선택 가능)
    /// @param shares 소각할 Share 수량
    /// @param receiver 출력 토큰을 수령할 주소
    /// @param outputToken 출력 토큰 주소 (USDT 또는 USDC만 허용)
    /// @param minOut 수령할 최소 출력 토큰 금액
    /// @param deadline 트랜잭션 유효 기한
    /// @return outAmount 수령한 출력 토큰 금액
    function redeemAs(uint256 shares, address receiver, address outputToken, uint256 minOut, uint256 deadline)
        external
        nonReentrant
        returns (uint256 outAmount)
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (shares == 0) revert InvalidShareAmount();
        if (paused() || factory.globalPaused()) revert VaultPaused();
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (shares > balanceOf(msg.sender)) revert InvalidShareAmount();

        address usdtAddr = asset();

        // 출력 토큰 검증: USDT 또는 USDC만 허용
        // TODO: USDC 주소는 Factory에서 조회하거나 초기화 시 설정하는 방식으로 개선 가능
        if (outputToken != usdtAddr) {
            // USDT가 아니면 Factory에 검증 위임 — 현재는 단순 확인
            // 향후 Factory에 isSettlementAsset(token) 추가 권장
            revert InvalidOutputToken(outputToken);
        }

        outAmount = _redeemShares(shares, msg.sender, receiver, outputToken, minOut);

        emit Redeemed(msg.sender, shares, outputToken, outAmount);
    }

    // =========================================================================
    // 리밸런싱
    // =========================================================================

    /// @notice 현재 자산 비중을 목표 비중으로 조정한다
    /// @dev creator: 정책 주기 무관, 슬리피지 상한 MAX_USER_SLIPPAGE_BPS(200bps).
    ///      비-creator(keeper): factory.isKeeper(msg.sender) 통과 + 정책 주기 충족 + 슬리피지 상한 NON_CREATOR_REBALANCE_HARDCAP_BPS(100bps).
    ///      MANUAL policy + 비-creator는 OnlyCreatorForManualPolicy revert.
    /// @param maxSlippageBps 허용 최대 슬리피지 (bps)
    function rebalance(uint256 maxSlippageBps) external nonReentrant {
        // 긴급 정지 상태에서는 리밸런싱 차단 (스왑 발생 방지)
        if (paused() || factory.globalPaused()) revert VaultPaused();

        bool isCreator = hasRole(CREATOR_ROLE, msg.sender);

        if (isCreator) {
            // creator는 사용자 입력 상한까지 자유롭게 호출 가능
            if (maxSlippageBps > MAX_USER_SLIPPAGE_BPS) revert InvalidSlippage();
        } else {
            // MANUAL policy는 creator 전용
            uint256 policySeconds = _policyToSeconds(rebalancePolicy);
            if (policySeconds == 0) revert OnlyCreatorForManualPolicy();

            // 정책 주기 충족
            uint256 nextAllowedAt = lastRebalancedAt + policySeconds;
            if (block.timestamp < nextAllowedAt) {
                revert RebalanceTooEarly(nextAllowedAt, block.timestamp);
            }

            // keeper allowlist 통과
            if (!factory.isKeeper(msg.sender)) revert KeeperNotAllowed(msg.sender);

            // 비-creator hardcap
            if (maxSlippageBps > NON_CREATOR_REBALANCE_HARDCAP_BPS) revert InvalidSlippage();
        }

        uint16[] memory beforeWeights = getCurrentWeights();

        _executeRebalance(maxSlippageBps);

        lastRebalancedAt = block.timestamp;

        uint16[] memory afterWeights = getCurrentWeights();

        emit Rebalanced(msg.sender, beforeWeights, afterWeights, block.timestamp);
    }

    // =========================================================================
    // 수수료 출금
    // =========================================================================

    /// @notice 누적된 수수료를 출금한다
    function withdrawFee() external nonReentrant {
        uint256 amount = accumulatedFees[msg.sender];
        if (amount == 0) revert NoFeeToWithdraw();

        accumulatedFees[msg.sender] = 0;
        totalPendingFees -= amount;

        IERC20(asset()).safeTransfer(msg.sender, amount);

        emit FeeWithdrawn(msg.sender, amount);
    }

    // =========================================================================
    // 일시정지 (AccessControl)
    // =========================================================================

    /// @notice Vault를 일시정지한다 — DEFAULT_ADMIN_ROLE(Factory)만 가능.
    /// @dev V5 부터 CREATOR_ROLE 의 pause 권한 제거. 정공 path: OPERATOR 가
    ///      `factory.pauseVault(vault)` 호출 → factory 가 vault.pause() 호출 (factory 가 vault 의
    ///      DEFAULT_ADMIN_ROLE 보유). CREATOR_ROLE 자체는 rebalance creator path 에 그대로 사용됨.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Vault 일시정지를 해제한다 — DEFAULT_ADMIN_ROLE(Factory)만 가능
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // =========================================================================
    // ERC-4626 오버라이드
    // =========================================================================

    /// @notice ERC4626 virtual shares offset — donation/inflation 공격 1차 보호.
    /// @dev OZ 표준 _convertToShares/_convertToAssets 경로(외부 view용)에 적용된다.
    ///      자체 deposit 코드는 supplyBefore/navBefore 캡처 + amountIn 기준 valueInUsdt(CONS-02-A)와
    ///      Factory의 minSeedAmount 하한으로 별도 보호한다.
    ///      V6 부터 ERC20 metadata(decimals)와 분리 — decimals() 는 6으로 별도 override.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return _DECIMALS_OFFSET;
    }

    /// @notice Share token decimals — V6 부터 6으로 명시 override.
    /// @dev OZ ERC4626 기본동작은 underlyingDecimals(USDT=6) + _decimalsOffset(6) = 12 를 반환하지만,
    ///      실제 share 발행 단위는 USDT raw(6 dec) 비례라 ERC20 metadata 와 실제 mint 단위가 어긋남.
    ///      외부 ERC20 viewer(MetaMask, Etherscan 등)가 사용자 잔액을 1/1e6 배로 표시하는 문제를 차단.
    ///      _decimalsOffset 의 inflation 보호는 _convertToShares/_convertToAssets 의 virtual offset 산식에서만
    ///      유지되며 ERC20 표시 단위와 무관.
    function decimals() public pure override(ERC4626Upgradeable) returns (uint8) {
        return 6;
    }

    /// @notice 오라클 기반 USDT 환산 NAV를 반환한다 (ERC-4626 totalAssets 오버라이드)
    function totalAssets() public view override returns (uint256 navInUsdt) {
        address baseAsset = asset();
        uint256 len = _vaultAssets.length;
        for (uint256 i = 0; i < len;) {
            address token = _vaultAssets[i];

            // Base asset(USDT)는 skip — 아래에서 잔액 전체로 처리 (이중 계산 방지)
            if (token == baseAsset) {
                unchecked { ++i; }
                continue;
            }

            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance > 0) {
                AssetConfig memory config = factory.getAssetConfig(token);
                uint256 price = _getChainlinkPrice(config);

                // USDT 환산: balance(tokenDecimals) × price(feedDecimals) → 6 decimals(USDT)
                uint256 totalDecimals = uint256(config.tokenDecimals) + uint256(config.feedDecimals);
                require(totalDecimals >= 6, "Invalid decimals config");
                uint256 divisor = 10 ** (totalDecimals - 6);
                navInUsdt += balance.mulDiv(price, divisor, Math.Rounding.Floor);
            }

            unchecked {
                ++i;
            }
        }

        // Vault 내 USDT 잔액에서 누적 미출금 수수료를 차감한 순 USDT 만 NAV 에 가산.
        // 수수료는 USDT denominated 청구권 (withdrawFee 가 USDT 만 송금) 이므로 자산 가치
        // 잠식 아님. USDT 잔액 < totalPendingFees 인 비정상 상태에서는 USDT 기여분 0 으로
        // clamp 하고 자산 가치만 NAV 에 반영 — getCurrentWeights USDT 분기 / redeem 의
        // usdtAvailable / _executeRebalance 와 회계 모델 일관성 확보.
        uint256 usdtBalance = IERC20(baseAsset).balanceOf(address(this));
        if (usdtBalance > totalPendingFees) {
            navInUsdt += usdtBalance - totalPendingFees;
        }
    }

    // =========================================================================
    // 조회 함수
    // =========================================================================

    /// @notice 기초자산 주소 배열을 반환
    function getAssets() external view returns (address[] memory) {
        return _vaultAssets;
    }

    /// @notice 목표 비중 배열을 반환 (bps)
    function getWeights() external view returns (uint16[] memory) {
        return _targetWeightsBps;
    }

    /// @notice 각 자산의 현재 Vault 잔고를 반환
    function getAssetBalances() external view returns (uint256[] memory balances) {
        uint256 len = _vaultAssets.length;
        balances = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            balances[i] = IERC20(_vaultAssets[i]).balanceOf(address(this));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice 오라클 가격 반영한 현재 실질 비중을 반환 (bps)
    function getCurrentWeights() public view returns (uint16[] memory weights) {
        uint256 len = _vaultAssets.length;
        weights = new uint16[](len);

        uint256 nav = totalAssets();
        if (nav == 0) return weights;

        address baseAsset = asset();
        for (uint256 i = 0; i < len;) {
            address token = _vaultAssets[i];

            if (token == baseAsset) {
                // Base asset(USDT): 잔액 - pendingFees = 순 USDT 가치 (1:1)
                uint256 usdtBalance = IERC20(baseAsset).balanceOf(address(this));
                uint256 netUsdt = usdtBalance > totalPendingFees ? usdtBalance - totalPendingFees : 0;
                if (netUsdt > 0) {
                    weights[i] = uint16(netUsdt.mulDiv(FEE_DENOMINATOR, nav, Math.Rounding.Floor));
                }
            } else {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance > 0) {
                    AssetConfig memory config = factory.getAssetConfig(token);
                    uint256 price = _getChainlinkPrice(config);
                    uint256 totalDecimals = uint256(config.tokenDecimals) + uint256(config.feedDecimals);
                    require(totalDecimals >= 6, "Invalid decimals config");
                    uint256 divisor = 10 ** (totalDecimals - 6);
                    uint256 valueInUsdt = balance.mulDiv(price, divisor, Math.Rounding.Floor);
                    weights[i] = uint16(valueInUsdt.mulDiv(FEE_DENOMINATOR, nav, Math.Rounding.Floor));
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice USDT 환산 총 NAV를 반환 (totalAssets와 동일)
    function getNAV() external view returns (uint256) {
        return totalAssets();
    }

    /// @notice NAV per Share를 반환 (USDT 6 decimals 기준)
    function getNAVPerShare() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return initialSharePrice;
        return totalAssets().mulDiv(PRECISION, supply, Math.Rounding.Floor);
    }

    /// @notice 생성자 주소를 반환
    function getCreator() external view returns (address) {
        return creator;
    }

    /// @notice 수수료율을 반환 (bps)
    function getFeeBps() external view returns (uint16) {
        return feeBps;
    }

    /// @notice 특정 수령인의 누적 수수료를 반환
    function getAccumulatedFee(address beneficiary) external view returns (uint256) {
        return accumulatedFees[beneficiary];
    }

    /// @notice 리밸런싱 정책을 반환
    function getRebalancePolicy() external view returns (RebalancePolicy) {
        return rebalancePolicy;
    }

    /// @notice 마지막 리밸런싱 시각을 반환
    function getLastRebalancedAt() external view returns (uint256) {
        return lastRebalancedAt;
    }

    /// @notice 다음 리밸런싱 가능 시각을 반환 (MANUAL이면 0)
    function getNextRebalanceAt() external view returns (uint256) {
        uint256 policySeconds = _policyToSeconds(rebalancePolicy);
        if (policySeconds == 0) return 0;
        return lastRebalancedAt + policySeconds;
    }

    /// @notice 사용자의 각 기초자산별 비례 청구권을 반환
    /// @param user 조회할 사용자 주소
    function getUserAssetBreakdown(address user) external view returns (address[] memory, uint256[] memory) {
        uint256 len = _vaultAssets.length;
        uint256[] memory amounts = new uint256[](len);

        uint256 supply = totalSupply();
        if (supply == 0) return (_vaultAssets, amounts);

        uint256 userShares = balanceOf(user);

        for (uint256 i = 0; i < len;) {
            uint256 vaultBalance = IERC20(_vaultAssets[i]).balanceOf(address(this));
            amounts[i] = vaultBalance.mulDiv(userShares, supply, Math.Rounding.Floor);
            unchecked {
                ++i;
            }
        }

        return (_vaultAssets, amounts);
    }

    // =========================================================================
    // 내부 함수 — 자산 매수/매도
    // =========================================================================

    /// @notice 목표 비중 기준으로 자산을 매수한다 (시드 예치 전용)
    /// @param usdtAmount 매수에 사용할 USDT 금액
    /// @param maxSlippageBps 자산 매수 시 허용 최대 슬리피지 (bps)
    /// @return deployedValue 실제 매수된 자산의 USDT 환산 총 가치
    function _buyAssetsAtTargetWeights(uint256 usdtAmount, uint256 maxSlippageBps)
        internal
        returns (uint256 deployedValue)
    {
        uint256 len = _vaultAssets.length;
        address usdtAddr = asset();
        address router = factory.swapRouter();

        for (uint256 i = 0; i < len;) {
            address token = _vaultAssets[i];
            uint256 alloc = usdtAmount.mulDiv(_targetWeightsBps[i], FEE_DENOMINATOR, Math.Rounding.Floor);

            if (alloc > 0) {
                if (token == usdtAddr) {
                    // Base asset(USDT)는 스왑 없이 보관 — 1:1 가치
                    deployedValue += alloc;
                } else {
                    deployedValue += _swapUSDTForAsset(usdtAddr, token, alloc, router, maxSlippageBps);
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice 지정된 비중으로 자산 매수 (deposit 전용 — USDT 전송 전 캡처한 비중 사용)
    /// @param usdtAmount 매수에 사용할 USDT 금액
    /// @param weights USDT 전송 전에 캡처한 자산 비중 배열
    /// @param maxSlippageBps 자산 매수 시 허용 최대 슬리피지 (bps)
    /// @return deployedValue 실제 매수된 자산의 USDT 환산 총 가치
    function _buyAssetsWithWeights(uint256 usdtAmount, uint16[] memory weights, uint256 maxSlippageBps)
        internal
        returns (uint256 deployedValue)
    {
        uint256 len = _vaultAssets.length;
        address usdtAddr = asset();
        address router = factory.swapRouter();

        for (uint256 i = 0; i < len;) {
            uint16 weight = weights[i];

            // 비중이 0이면 목표 비중으로 폴백
            if (weight == 0) {
                weight = _targetWeightsBps[i];
            }

            uint256 alloc = usdtAmount.mulDiv(weight, FEE_DENOMINATOR, Math.Rounding.Floor);

            if (alloc > 0) {
                if (_vaultAssets[i] == usdtAddr) {
                    // Base asset(USDT)는 스왑 없이 보관
                    deployedValue += alloc;
                } else {
                    deployedValue += _swapUSDTForAsset(usdtAddr, _vaultAssets[i], alloc, router, maxSlippageBps);
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice USDT → 기초자산 스왑 실행 (Oracle 기반 슬리피지 보호 + 가치 평가)
    /// @param usdtAddr USDT 토큰 주소
    /// @param tokenOut 매수할 기초자산 주소
    /// @param amountIn 스왑할 USDT 금액
    /// @param router Uniswap V3 라우터 주소
    /// @param maxSlippageBps 허용 최대 슬리피지 (bps). 0이면 슬리피지 보호 없음.
    /// @return valueInUsdt 매수된 자산의 USDT 환산 가치 (Oracle 기준)
    function _swapUSDTForAsset(address usdtAddr, address tokenOut, uint256 amountIn, address router, uint256 maxSlippageBps)
        internal
        returns (uint256 valueInUsdt)
    {
        AssetConfig memory config = factory.getAssetConfig(tokenOut);

        // Chainlink 가격 기반 최소 수령 자산량 계산 (슬리피지 보호)
        uint256 price = _getChainlinkPrice(config);
        uint256 totalDecimals = uint256(config.tokenDecimals) + uint256(config.feedDecimals);
        require(totalDecimals >= 6, "Invalid decimals config");
        uint256 divisor = 10 ** (totalDecimals - 6);

        // oracleOut = amountIn(USDT, 6dec) * divisor / price → tokenOut 단위
        uint256 oracleOut = amountIn.mulDiv(divisor, price, Math.Rounding.Floor);

        // 슬리피지 반영 최소값
        uint256 amountOutMinimum = 0;
        if (maxSlippageBps < FEE_DENOMINATOR) {
            amountOutMinimum = oracleOut.mulDiv(FEE_DENOMINATOR - maxSlippageBps, FEE_DENOMINATOR, Math.Rounding.Floor);
        }

        IERC20(usdtAddr).forceApprove(router, amountIn);

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdtAddr,
                tokenOut: tokenOut,
                fee: config.uniswapFeeTier,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );

        // CONS-02-A: 슬리피지 손실은 vault 전체 NAV에 균등 흡수되도록 amountIn 기준으로 가산.
        //            (received 기준이면 deposit user에게 손실이 몰리고 기존 holder의 share 비율이 왜곡됨)
        //            amountOutMinimum 보호가 사전 검사를 수행하므로 received < oracleOut 손실은
        //            totalAssets() 다음 계산 시점에 자연스럽게 NAV 감소로 반영된다.
        valueInUsdt = amountIn;
    }

    /// @notice 기초자산 → USDT 스왑 실행
    /// @dev CONS-07: 외부 호출자가 던진 `minUsdtOut`(누적 보호) 위에 내부에서 oracle 기반
    ///      leg별 minOut(`PER_LEG_SLIPPAGE_BPS`)을 자동 적용한다. 두 minOut 중 더 큰 값을 채택.
    /// @param tokenIn 매도할 기초자산 주소
    /// @param amountIn 스왑할 기초자산 금액
    /// @param router Uniswap V3 라우터 주소
    /// @param minUsdtOut 외부 호출자가 강제하는 최소 USDT 금액 (누적 보호)
    /// @return usdtOut 수령한 USDT 금액
    function _swapAssetForUSDT(address tokenIn, uint256 amountIn, address router, uint256 minUsdtOut)
        internal
        returns (uint256 usdtOut)
    {
        AssetConfig memory config = factory.getAssetConfig(tokenIn);
        address usdtAddr = asset();

        // CONS-07: leg별 oracle 기반 minOut 자동 계산
        uint256 price = _getChainlinkPrice(config);
        uint256 totalDecimals = uint256(config.tokenDecimals) + uint256(config.feedDecimals);
        require(totalDecimals >= 6, "Invalid decimals config");
        uint256 divisor = 10 ** (totalDecimals - 6);
        uint256 oracleQuote = amountIn.mulDiv(price, divisor, Math.Rounding.Floor);
        uint256 perLegMinOut =
            oracleQuote.mulDiv(FEE_DENOMINATOR - PER_LEG_SLIPPAGE_BPS, FEE_DENOMINATOR, Math.Rounding.Floor);
        uint256 effectiveMinOut = minUsdtOut > perLegMinOut ? minUsdtOut : perLegMinOut;

        uint256 balanceBefore = IERC20(usdtAddr).balanceOf(address(this));

        IERC20(tokenIn).forceApprove(router, amountIn);

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: usdtAddr,
                fee: config.uniswapFeeTier,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: effectiveMinOut,
                sqrtPriceLimitX96: 0
            })
        );

        usdtOut = IERC20(usdtAddr).balanceOf(address(this)) - balanceBefore;
    }

    // =========================================================================
    // 내부 함수 — 환매
    // =========================================================================

    /// @notice Share를 소각하고 pro-rata 비율로 자산을 매도하여 outputToken을 반환한다
    /// @param shares 소각할 Share 수량
    /// @param burner Share 소각 대상 주소 (redeem: owner, redeemAs: msg.sender)
    /// @param receiver 출력 토큰 수령 주소
    /// @param outputToken 출력 토큰 주소
    /// @param minOut 최소 수령 출력 토큰 금액
    function _redeemShares(uint256 shares, address burner, address receiver, address outputToken, uint256 minOut)
        internal
        returns (uint256 outAmount)
    {
        // Checks
        uint256 supply = totalSupply();
        address router = factory.swapRouter();
        address usdtAddr = asset();
        uint256 len = _vaultAssets.length;

        // USDT 잔고 pro-rata 몫 계산 (스왑 전, pendingFees 제외)
        // totalAssets()가 USDT 잔고를 NAV에 포함하므로 환매 시에도 분배해야 공정
        uint256 usdtBalance = IERC20(usdtAddr).balanceOf(address(this));
        uint256 usdtAvailable = usdtBalance > totalPendingFees ? usdtBalance - totalPendingFees : 0;
        uint256 usdtPortion = usdtAvailable.mulDiv(shares, supply, Math.Rounding.Floor);

        // Effects — CEI 패턴: burn을 외부 호출(스왑) 전에 실행
        _burn(burner, shares);

        // Interactions — pro-rata 계산은 burn 전 supply 기준 (위에서 캡처)
        // 1. 투자 자산 매도 (base asset은 skip — USDT pro-rata에서 처리)
        for (uint256 i = 0; i < len;) {
            address token = _vaultAssets[i];

            if (token != usdtAddr) {
                uint256 vaultBalance = IERC20(token).balanceOf(address(this));
                uint256 tokenOut = vaultBalance.mulDiv(shares, supply, Math.Rounding.Floor);

                if (tokenOut > 0) {
                    outAmount += _swapAssetForUSDT(token, tokenOut, router, 0);
                }
            }

            unchecked {
                ++i;
            }
        }

        // 2. USDT 잔고 pro-rata 몫 추가 (의도적 보관분 + dust 모두 포함)
        outAmount += usdtPortion;

        if (outAmount < minOut) revert SlippageExceeded(outAmount, minOut);

        // 출력 토큰 전송
        IERC20(outputToken).safeTransfer(receiver, outAmount);
    }

    // =========================================================================
    // 내부 함수 — 리밸런싱
    // =========================================================================

    /// @notice 리밸런싱을 실행한다 — 초과 자산 매도 → 부족 자산 매수
    function _executeRebalance(uint256 maxSlippageBps) internal {
        uint256 len = _vaultAssets.length;
        address usdtAddr = asset();
        address router = factory.swapRouter();

        uint16[] memory currentWeights = getCurrentWeights();
        uint256 nav = totalAssets();

        // 1단계: 초과 자산 매도 (현재 비중 > 목표 비중)
        // Base asset(USDT)는 매도 불필요 — 비중 조정은 다른 자산 매수/매도로 자동 달성
        for (uint256 i = 0; i < len;) {
            uint16 current = currentWeights[i];
            uint16 target = _targetWeightsBps[i];

            if (current > target && _vaultAssets[i] != usdtAddr) {
                address token = _vaultAssets[i];
                uint256 vaultBalance = IERC20(token).balanceOf(address(this));

                // 초과 비중에 해당하는 자산량 계산
                uint256 excessValue = nav.mulDiv(current - target, FEE_DENOMINATOR, Math.Rounding.Floor);
                AssetConfig memory config = factory.getAssetConfig(token);
                uint256 price = _getChainlinkPrice(config);
                uint256 totalDecimals = uint256(config.tokenDecimals) + uint256(config.feedDecimals);
                require(totalDecimals >= 6, "Invalid decimals config");
                uint256 divisor = 10 ** (totalDecimals - 6);

                // excessValue(USDT) → token량
                uint256 excessTokens = excessValue.mulDiv(divisor, price, Math.Rounding.Ceil);
                if (excessTokens > vaultBalance) excessTokens = vaultBalance;

                if (excessTokens > 0) {
                    uint256 slipDenom = uint256(FEE_DENOMINATOR);
                    uint256 minUsdtOut = maxSlippageBps < slipDenom
                        ? excessValue.mulDiv(slipDenom - maxSlippageBps, slipDenom, Math.Rounding.Floor)
                        : 0;
                    _swapAssetForUSDT(token, excessTokens, router, minUsdtOut);
                }
            }

            unchecked {
                ++i;
            }
        }

        // 2단계: 부족 자산 매수 (현재 비중 < 목표 비중)
        // 1단계 매도로 확보된 USDT 잔고를 재계산
        uint256 availableUsdt = IERC20(usdtAddr).balanceOf(address(this));
        // 수수료 보관분 제외 — 미출금 수수료는 운용 자금이 아니므로 매수에 사용하면 안 됨
        {
            if (totalPendingFees >= availableUsdt) {
                availableUsdt = 0;
            } else {
                availableUsdt -= totalPendingFees;
            }
        }

        if (availableUsdt > 0) {
            // 부족 비중 합계 계산 (base asset 제외 — USDT는 매수 불필요)
            uint16[] memory updatedWeights = getCurrentWeights();
            uint256 deficitSum;
            for (uint256 i = 0; i < len;) {
                if (_vaultAssets[i] != usdtAddr && updatedWeights[i] < _targetWeightsBps[i]) {
                    deficitSum += _targetWeightsBps[i] - updatedWeights[i];
                }
                unchecked {
                    ++i;
                }
            }

            if (deficitSum > 0) {
                for (uint256 i = 0; i < len;) {
                    if (updatedWeights[i] < _targetWeightsBps[i] && _vaultAssets[i] != usdtAddr) {
                        uint16 deficit = _targetWeightsBps[i] - updatedWeights[i];
                        uint256 alloc = availableUsdt.mulDiv(deficit, deficitSum, Math.Rounding.Floor);

                        if (alloc > 0) {
                            _swapUSDTForAsset(usdtAddr, _vaultAssets[i], alloc, router, maxSlippageBps);
                        }
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    // =========================================================================
    // 내부 함수 — 오라클
    // =========================================================================

    /// @notice Chainlink 가격 피드에서 최신 가격을 조회한다
    /// @param config 자산 설정 (priceFeed + maxPriceAge 사용)
    /// @return price 가격 (feedDecimals 소수점)
    /// @dev 자산별 maxPriceAge 사용 — XAU/USD 24h heartbeat 같은 long-heartbeat feed 대응 (CONS-06).
    ///      `answeredInRound < roundId` 추가 검증으로 incomplete round 차단.
    function _getChainlinkPrice(AssetConfig memory config) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            IAggregatorV3(config.priceFeed).latestRoundData();

        if (answer <= 0) revert InvalidPrice(config.token);
        if (answeredInRound < roundId) revert StalePrice(config.token);
        if (block.timestamp - updatedAt > config.maxPriceAge) revert StalePrice(config.token);

        price = uint256(answer);
    }

    // =========================================================================
    // 내부 함수 — Share 계산
    // =========================================================================

    /// @notice 투입 가치(USDT)를 기반으로 발행할 Share 수량을 계산한다

    // =========================================================================
    // 내부 함수 — 정책 변환
    // =========================================================================

    /// @notice 리밸런싱 정책을 초 단위로 변환한다 (MANUAL = 0)
    function _policyToSeconds(RebalancePolicy policy) internal pure returns (uint256) {
        if (policy == RebalancePolicy.MONTHLY) return 30 days;
        if (policy == RebalancePolicy.QUARTERLY) return 90 days;
        if (policy == RebalancePolicy.SEMI_ANNUAL) return 180 days;
        return 0; // MANUAL
    }

    // =========================================================================
    // ERC-4626 오버라이드 — 표준 deposit/withdraw/mint/redeem 비활성화
    // =========================================================================

    /// @notice 표준 ERC-4626 deposit을 비활성화 — 커스텀 deposit(uint256,address,uint256,uint256) 사용
    function deposit(uint256, address) public virtual override returns (uint256) {
        revert ERC4626Disabled();
    }

    /// @notice 표준 ERC-4626 mint를 비활성화 — 미지원
    function mint(uint256, address) public virtual override returns (uint256) {
        revert ERC4626Disabled();
    }

    /// @notice 표준 ERC-4626 withdraw를 비활성화 — 미지원
    function withdraw(uint256, address, address) public virtual override returns (uint256) {
        revert ERC4626Disabled();
    }

    /// @notice 표준 ERC-4626 redeem을 비활성화 — 커스텀 redeem(uint256,address,address,uint256,uint256) 사용
    function redeem(uint256, address, address) public virtual override returns (uint256) {
        revert ERC4626Disabled();
    }
}
