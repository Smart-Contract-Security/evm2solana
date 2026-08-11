// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokinsoCore is Initializable, ERC20Upgradeable, OwnableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ======== Roles ========
    bytes32 public constant NAV_OPERATOR_ROLE = keccak256("NAV_OPERATOR_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant BANK_ROLE = keccak256("BANK_ROLE");

    // ======== Legacy storage kept for upgrade safety ========
    uint256 public totalVaultValue;
    uint256 public nav;
    uint256 public constant PRECISION = 1e18;

    // ======== Constants ========
    uint256 internal constant USD_DECIMALS = 1e6; // NAV and vault values
    uint256 internal constant USD_TO_18 = 1e12;   // multiplier to convert 6d USD -> 18d
    uint256 internal constant MIDDAY_CUTOFF = 12 hours;
    uint256 internal constant AUTO_PUBLISH_OFFSET = 11 hours + 58 minutes;
    int256 internal constant MIN_UTC_OFFSET = -12 hours;
    int256 internal constant MAX_UTC_OFFSET = 14 hours;
    // Excel target model: no effective daily redemption cap during replay scenarios.
    uint256 public constant DAILY_REDEMPTION_LIMIT_BPS = 10000; // 100% (no cap)
    uint256 public constant MANAGEMENT_FEE_BPS = 150; // 1.5% par mois
    // Excel target model: 20% performance fee above HWM.
    uint256 public constant PERFORMANCE_FEE_BPS = 2000; // 20%
    uint256 internal constant MIN_DAYS_BETWEEN_MGMT_FEES = 30;

    // ======== NAV state ========
    uint256 public currentTotalValueUSD;
    uint256 public currentNavPerTokenUSD;
    uint256 public currentEthUsdPrice;
    uint256 public lastNavTimestamp;
    uint256 public lastNavDayId;
    bool public restatedToday;

    struct NavSnapshot {
        uint256 totalValueUSD;
        uint256 navPerTokenUSD;
        uint256 ethUsdPrice;
        uint256 timestamp;
        bool restated;
    }

    mapping(uint256 => NavSnapshot) public dailyNavs;

    // ======== Order book ========
    enum OrderType { Subscription, Redemption }

    struct Order {
        address user;
        OrderType orderType;
        uint256 amount;       // USDC amount for subscriptions, token amount for redemptions
        uint256 submittedAt;
        uint256 navDayId;     // day ID for which the NAV will be used
        bool beforeCutoff;    // true if submitted before 12h UTC
        bool processed;
    }

    Order[] internal orders;
    mapping(uint256 => uint256[]) internal ordersByNavDay;
    mapping(address => uint256) public lockedRedemptionTokens;

    // ======== Fees ========
    address public feeRecipient;
    address public usdcToken;
    uint256 public lastMgmtFeeDayId;
    uint256 public lastMgmtAccrualDayId;
    uint256 public accruedManagementFeeUSD;
    uint256 public highWaterMark;
    uint256 public accruedPerformanceFeeUSD;
    uint256 public crystallizedPerformanceFeeUSD;
    uint256 public yearEndPerformanceFeeUSD;
    uint256 public lastPerfFeeYear;
    uint256 public lastPerfFeeMonthId;
    uint256 public lastPerfFeeTimestamp;
    uint256 public lastPerfAccrualDayId;
    uint256 public lastHwmResetYear;

    // ======== Pending NAV (draft -> approve) ========
    uint256 public pendingNavDayId;
    uint256 public pendingNavTotalValueUSD;
    uint256 public pendingNavPerTokenUSD;
    uint256 public pendingNavAsOfTimestamp;
    bool public pendingNavExists;
    bool public pendingNavApproved;
    int256 public localTimeUtcOffset;

    // ========= Utils =========
    function accruePerformanceFee() internal virtual;
    function _accruePerformanceFeeForDay(uint256 dayId, uint256 navPerTokenBeforePerf) internal virtual {}
    function _onRedemptionCrystallizePerfFee(uint256 usdAmount18, uint256 totalValueUSD) internal virtual {}

    function _dayId(uint256 ts) internal pure returns (uint256) {
        return ts / 1 days;
    }

    function _localTimestamp(uint256 ts) internal view returns (uint256) {
        int256 shifted = int256(ts) + localTimeUtcOffset;
        require(shifted >= 0, "Timestamp local invalide");
        return uint256(shifted);
    }

    function _localDayId(uint256 ts) internal view returns (uint256) {
        return _localTimestamp(ts) / 1 days;
    }

    function _utcFromLocalDayStart(uint256 localDayId) internal view returns (uint256) {
        int256 utcTs = int256(localDayId * 1 days) - localTimeUtcOffset;
        require(utcTs >= 0, "Jour local invalide");
        return uint256(utcTs);
    }

    function _autoPublishThresholdUtc(uint256 localDayId) internal view returns (uint256) {
        return _utcFromLocalDayStart(localDayId) + AUTO_PUBLISH_OFFSET;
    }

    function _yearId(uint256 ts) internal pure returns (uint256) {
        return 1970 + (_dayId(ts) / 365);
    }

    function _isYearEnd(uint256 ts) internal pure returns (bool) {
        uint256 dayOfYear = _dayId(ts) % 365;
        return dayOfYear == 364;
    }

    function _isBeforeCutoff(uint256 ts) internal view returns (bool) {
        return (_localTimestamp(ts) % 1 days) < MIDDAY_CUTOFF;
    }

    function _navDayForOrder(uint256 ts) internal view returns (uint256) {
        uint256 dayId = _localDayId(ts);
        // Execution rule with noon cutoff:
        // - order submitted before 12:00 local time uses NAV of next day (J+1)
        // - order submitted at/after 12:00 local time uses NAV of day after next (J+2)
        // Example: 1 Mar 12:00 -> 2 Mar 11:59:59 uses NAV of 3 Mar.
        uint256 timeOfDay = _localTimestamp(ts) % 1 days;
        if (timeOfDay >= MIDDAY_CUTOFF) {
            return dayId + 2;
        }
        return dayId + 1;
    }

    function _setLocalTimeUtcOffset(int256 newOffset) internal {
        require(newOffset >= MIN_UTC_OFFSET && newOffset <= MAX_UTC_OFFSET, "Offset UTC invalide");
        int256 oldOffset = localTimeUtcOffset;
        localTimeUtcOffset = newOffset;
        emit LocalTimeUtcOffsetUpdated(oldOffset, newOffset);
    }

    function setLocalTimeUtcOffset(int256 newOffset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setLocalTimeUtcOffset(newOffset);
    }

    function _tokenAmountToUsd18(uint256 tokenAmount, uint256 navPerTokenUSD) internal pure returns (uint256) {
        return (tokenAmount * navPerTokenUSD) / USD_DECIMALS;
    }

    function _netAssetValueUSDExcludingPerf(uint256 grossValueUSD) internal view returns (uint256) {
        // Excel-aligned model:
        // crystallizedPerformanceFeeUSD is a reclassification of perf provision,
        // not an additional deduction in NAV computation.
        uint256 totalAccrued = accruedManagementFeeUSD + yearEndPerformanceFeeUSD;
        if (grossValueUSD > totalAccrued) {
            return grossValueUSD - totalAccrued;
        }
        return 0;
    }

    function _netAssetValueUSD(uint256 grossValueUSD) internal view returns (uint256) {
        // Keep accrued perf in NAV drag, but exclude crystallized bucket to avoid
        // double-impact when provisions are moved from accrued -> crystallized.
        uint256 totalAccrued = accruedManagementFeeUSD + accruedPerformanceFeeUSD + yearEndPerformanceFeeUSD;
        if (grossValueUSD > totalAccrued) {
            return grossValueUSD - totalAccrued;
        }
        return 0;
    }

    function _payoutUSD(uint256 usdAmount) internal returns (uint256 usdcAmount) {
        require(usdAmount > 0, "Montant nul");
        require(usdcToken != address(0), "USDC non configure");

        if (currentTotalValueUSD > usdAmount) {
            currentTotalValueUSD -= usdAmount;
        } else {
            currentTotalValueUSD = 0;
        }

        IERC20(usdcToken).safeTransfer(feeRecipient, usdAmount);
        return usdAmount;
    }

    function _accrueManagementFeeForDay(
        uint256 dayId,
        uint256 totalValueUSD,
        bool revertOnNoOp
    ) internal {
        if (totalValueUSD == 0) {
            if (revertOnNoOp) revert("NAV non definie");
            return;
        }
        if (dayId <= lastMgmtAccrualDayId) {
            if (revertOnNoOp) revert("Deja provisionne");
            return;
        }
        uint256 feeUSD = ((totalValueUSD * MANAGEMENT_FEE_BPS) / 10000) / 365;
        if (feeUSD == 0) {
            if (revertOnNoOp) revert("Frais nuls");
            lastMgmtAccrualDayId = dayId;
            return;
        }
        accruedManagementFeeUSD += feeUSD;
        lastMgmtAccrualDayId = dayId;

        emit ManagementFeeAccrued(feeUSD, accruedManagementFeeUSD, dayId);
    }

    // ========= Events =========
    event NavUpdated(uint256 indexed dayId, uint256 totalValueUSD, uint256 navPerTokenUSD, uint256 ethUsdPrice);
    event NavRestated(uint256 indexed dayId, uint256 correctedTotalValueUSD, uint256 correctedNavPerTokenUSD, uint256 correctedEthUsdPrice);
    event NavDrafted(uint256 indexed dayId, uint256 totalValueUSD, uint256 navPerTokenUSD, uint256 asOfTimestamp);
    event NavApproved(uint256 indexed dayId, uint256 totalValueUSD, uint256 navPerTokenUSD);
    event NavValidated(uint256 indexed dayId, uint256 totalValueUSD, uint256 navPerTokenUSD);
    event EthUsdPriceUpdated(uint256 newPrice);
    event FeeRecipientUpdated(address indexed newRecipient);
    event UsdcTokenUpdated(address indexed newToken);
    event ManagementFeeAccrued(uint256 feeUsd, uint256 totalAccruedUsd, uint256 indexed dayId);
    event ManagementFeeCollected(uint256 feeUsd, uint256 feeWei, uint256 indexed dayId);
    event PerformanceFeeCollected(uint256 feeUsd, uint256 feeWei, uint256 newHighWaterMark, uint256 indexed yearId);
    event LocalTimeUtcOffsetUpdated(int256 oldOffset, int256 newOffset);
    event OrderQueued(
        uint256 indexed orderId,
        address indexed user,
        OrderType orderType,
        uint256 amount,
        uint256 indexed navDayId,
        bool beforeCutoff
    );
    event OrderProcessed(uint256 indexed navDayId, uint256 indexed orderId, OrderType orderType, uint256 processedAmount);
    event OrderDeferred(uint256 indexed fromNavDayId, uint256 indexed toNavDayId, address indexed user, uint256 amountCarried);
}
