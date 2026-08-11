// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokinsoCore.sol";
import "./TokinsoOrdersModule.sol";

abstract contract TokinsoNavModule is TokinsoCore, TokinsoOrdersModule {
    // ========= Admin functions =========
    function submitDailyNAV(uint256 totalValueUSD, uint256 asOfTimestamp) external onlyRole(NAV_OPERATOR_ROLE) {
        draftDailyNAV(totalValueUSD, asOfTimestamp);
        if (_canPublishPendingNAV(pendingNavDayId)) {
            _publishPendingNAV();
        }
    }

    function draftDailyNAV(uint256 totalValueUSD, uint256 asOfTimestamp) public onlyRole(NAV_OPERATOR_ROLE) returns (uint256) {
        uint256 dayId = _localDayId(asOfTimestamp);
        require(dayId >= lastNavDayId, "Backdating not allowed");
        require(totalValueUSD > 0, "Valeur USD invalide");

        _accrueManagementFeeForDay(dayId, totalValueUSD, false);
        uint256 navBeforePerf = _computeNavPerTokenUSD(totalValueUSD, true);
        _accruePerformanceFeeForDay(dayId, navBeforePerf);
        uint256 navPerTokenUSD = _computeNavPerTokenUSD(totalValueUSD, false);
        pendingNavDayId = dayId;
        pendingNavTotalValueUSD = totalValueUSD;
        pendingNavPerTokenUSD = navPerTokenUSD;
        pendingNavAsOfTimestamp = asOfTimestamp;
        pendingNavExists = true;
        pendingNavApproved = false;

        emit NavDrafted(dayId, totalValueUSD, navPerTokenUSD, asOfTimestamp);
        return navPerTokenUSD;
    }

    function approvePendingNAV() external onlyRole(NAV_OPERATOR_ROLE) {
        require(pendingNavExists, "NAV inexistante");
        pendingNavApproved = true;
        emit NavValidated(pendingNavDayId, pendingNavTotalValueUSD, pendingNavPerTokenUSD);
    }

    function autoPublishNAV() external {
        require(pendingNavExists, "NAV inexistante");
        require(block.timestamp >= _autoPublishThresholdUtc(pendingNavDayId), "Auto-publish trop tot");
        _publishPendingNAV();
    }

    function restateNAV(uint256 correctedTotalValueUSD) external onlyRole(NAV_OPERATOR_ROLE) {
        require(!restatedToday, "Restatement already used today");
        require(lastNavDayId == _localDayId(block.timestamp), "Only same-day restatement");

        currentTotalValueUSD = correctedTotalValueUSD;
        currentEthUsdPrice = 0;
        uint256 navBeforePerf = _computeNavPerTokenUSD(correctedTotalValueUSD, true);
        _accruePerformanceFeeForDay(_dayId(block.timestamp), navBeforePerf);
        currentNavPerTokenUSD = _computeNavPerTokenUSD(correctedTotalValueUSD, false);

        restatedToday = true;

        NavSnapshot storage snap = dailyNavs[lastNavDayId];
        snap.totalValueUSD = correctedTotalValueUSD;
        snap.navPerTokenUSD = currentNavPerTokenUSD;
        snap.ethUsdPrice = 0;
        snap.timestamp = block.timestamp;
        snap.restated = true;

        emit NavRestated(lastNavDayId, correctedTotalValueUSD, currentNavPerTokenUSD, 0);
    }

    // ========= Pending NAV helpers =========
    function _computeNavPerTokenUSD(uint256 totalValueUSD, bool excludePerf) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 netAssetValueUSD = excludePerf
            ? _netAssetValueUSDExcludingPerf(totalValueUSD)
            : _netAssetValueUSD(totalValueUSD);
        if (supply == 0) {
            return 100 * USD_DECIMALS;
        }
        return (netAssetValueUSD * 1e18) / supply;
    }

    function _canPublishPendingNAV(uint256 dayId) internal view returns (bool) {
        return block.timestamp >= _autoPublishThresholdUtc(dayId);
    }

    function _publishPendingNAV() internal {
        require(pendingNavExists, "NAV inexistante");
        require(pendingNavDayId >= lastNavDayId, "Backdating not allowed");

        restatedToday = false;
        lastNavDayId = pendingNavDayId;

        currentTotalValueUSD = pendingNavTotalValueUSD;
        currentEthUsdPrice = 0;
        lastNavTimestamp = block.timestamp;
        currentNavPerTokenUSD = pendingNavPerTokenUSD;

        uint256 navYear = _yearId(pendingNavAsOfTimestamp);
        if (_isYearEnd(pendingNavAsOfTimestamp) || navYear > lastHwmResetYear) {
            yearEndPerformanceFeeUSD += accruedPerformanceFeeUSD;
            accruedPerformanceFeeUSD = 0;
            highWaterMark = currentNavPerTokenUSD;
            lastHwmResetYear = navYear;
        }

        dailyNavs[pendingNavDayId] = NavSnapshot({
            totalValueUSD: pendingNavTotalValueUSD,
            navPerTokenUSD: pendingNavPerTokenUSD,
            ethUsdPrice: 0,
            timestamp: block.timestamp,
            restated: false
        });

        emit NavUpdated(pendingNavDayId, pendingNavTotalValueUSD, pendingNavPerTokenUSD, 0);
        emit NavApproved(pendingNavDayId, pendingNavTotalValueUSD, pendingNavPerTokenUSD);

        _rollForwardUnprocessedOrders(pendingNavDayId);
        _processOrdersForNavDay(pendingNavDayId, pendingNavPerTokenUSD, pendingNavTotalValueUSD);

        pendingNavExists = false;
        pendingNavApproved = false;
    }

    // ========= Views =========
    function getCurrentNavPerTokenUSD() external view returns (uint256) {
        return currentNavPerTokenUSD;
    }

    function getCurrentTotalValueUSD() external view returns (uint256) {
        return currentTotalValueUSD;
    }

    function getLastNavDayId() external view returns (uint256) {
        return lastNavDayId;
    }
}
