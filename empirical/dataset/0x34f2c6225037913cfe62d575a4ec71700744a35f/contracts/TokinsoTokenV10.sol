// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokinsoNavModule.sol";
import "./TokinsoOrdersModule.sol";
import "./TokinsoFeesModule.sol";
import "./TokinsoPerfFeeModule.sol";

/**
 * TokinsoToken V10 — Multi-role access control + UUPS upgradeable proxy.
 *
 * Extends V9 by replacing single-owner access with granular roles:
 *  - DEFAULT_ADMIN_ROLE : Gnosis Safe multisig — manages roles, upgrades, critical params
 *  - NAV_OPERATOR_ROLE  : Publishes/drafts/approves/restates daily NAV
 *  - FEE_MANAGER_ROLE   : Accrues and collects management & performance fees
 *  - BANK_ROLE          : Manages treasury (USDC token, fee recipient address)
 *
 * Owner (OwnableUpgradeable) is kept solely for _authorizeUpgrade (UUPS standard).
 * Owner should be the same Gnosis Safe as DEFAULT_ADMIN_ROLE.
 */
contract TokinsoTokenV10 is TokinsoNavModule, TokinsoFeesModule, TokinsoPerfFeeModule {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    /**
     * @notice Initialize the contract with multi-role addresses.
     * @param admin       Gnosis Safe multisig — gets DEFAULT_ADMIN_ROLE + Owner + all roles initially
     * @param navOperator Address authorized to publish NAV (can be a hot wallet / backend)
     * @param feeManager  Address authorized to accrue/collect fees
     * @param bank        Treasury address — manages USDC config and fee recipient
     */
    function initialize(
        address admin,
        address navOperator,
        address feeManager,
        address bank
    ) public initializer {
        require(admin != address(0), "Admin zero address");
        require(navOperator != address(0), "NAV operator zero address");
        require(feeManager != address(0), "Fee manager zero address");
        require(bank != address(0), "Bank zero address");

        __ERC20_init("Tokinso Dev", "INSDEV1");
        __Ownable_init(admin);           // Owner = Gnosis Safe (for UUPS upgrades)
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _setLocalTimeUtcOffset(1 hours);

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(NAV_OPERATOR_ROLE, navOperator);
        _grantRole(FEE_MANAGER_ROLE, feeManager);
        _grantRole(BANK_ROLE, bank);

        // Seed launch state: day 0 starts with 1 INS bought at 100 USD.
        uint256 launchTotalValueUSD = 100 * USD_DECIMALS;
        _mint(admin, 1e18);

        currentTotalValueUSD = launchTotalValueUSD;
        currentNavPerTokenUSD = _computeNavPerTokenUSD(launchTotalValueUSD, false);
        currentEthUsdPrice = 0;
        lastNavTimestamp = block.timestamp;
        lastNavDayId = _localDayId(block.timestamp);

        totalVaultValue = 0;
        nav = PRECISION;
        feeRecipient = bank;  // Bank address receives fees by default
        lastMgmtFeeDayId = lastNavDayId >= MIN_DAYS_BETWEEN_MGMT_FEES
            ? lastNavDayId - MIN_DAYS_BETWEEN_MGMT_FEES
            : 0;
        lastMgmtAccrualDayId = lastNavDayId;
        accruedManagementFeeUSD = 0;
        highWaterMark = currentNavPerTokenUSD;
        lastPerfFeeYear = _yearId(block.timestamp);
        lastPerfFeeTimestamp = block.timestamp;
        accruedPerformanceFeeUSD = 0;
        crystallizedPerformanceFeeUSD = 0;
        yearEndPerformanceFeeUSD = 0;
        lastPerfAccrualDayId = lastNavDayId;
        lastHwmResetYear = lastPerfFeeYear;

        dailyNavs[lastNavDayId] = NavSnapshot({
            totalValueUSD: launchTotalValueUSD,
            navPerTokenUSD: currentNavPerTokenUSD,
            ethUsdPrice: 0,
            timestamp: block.timestamp,
            restated: false
        });

        emit NavUpdated(lastNavDayId, launchTotalValueUSD, currentNavPerTokenUSD, 0);
    }

    // ========= UUPS Upgrade Authorization =========
    // Only the Owner (Gnosis Safe) can authorize upgrades
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ========= Diamond override resolution =========
    function _accruePerformanceFeeForDay(
        uint256 dayId,
        uint256 navPerTokenBeforePerf
    ) internal override(TokinsoCore, TokinsoPerfFeeModule) {
        TokinsoPerfFeeModule._accruePerformanceFeeForDay(dayId, navPerTokenBeforePerf);
    }

    function _onRedemptionCrystallizePerfFee(
        uint256 usdAmount18,
        uint256 totalValueUSD
    ) internal override(TokinsoCore, TokinsoPerfFeeModule) {
        TokinsoPerfFeeModule._onRedemptionCrystallizePerfFee(usdAmount18, totalValueUSD);
    }

    // ========= Utility views =========
    function version() external pure returns (string memory) {
        return "V10-MULTI-ROLE-DEV1";
    }

    /// @notice Check if an address has a specific role (convenience view)
    function hasTokinsoRole(bytes32 role, address account) external view returns (bool) {
        return hasRole(role, account);
    }
}
