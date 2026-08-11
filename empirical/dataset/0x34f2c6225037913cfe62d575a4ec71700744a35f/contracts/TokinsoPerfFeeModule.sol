// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokinsoCore.sol";

abstract contract TokinsoPerfFeeModule is TokinsoCore {
    // ========= Admin functions =========
    function recordHWM() external onlyRole(FEE_MANAGER_ROLE) {
        if (currentNavPerTokenUSD > highWaterMark) {
            highWaterMark = currentNavPerTokenUSD;
        }
    }

    function HWM() external onlyRole(FEE_MANAGER_ROLE) {
        if (currentNavPerTokenUSD > highWaterMark) {
            highWaterMark = currentNavPerTokenUSD;
        }
    }

    function accruePerfFee(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        uint256 dayId = _dayId(asOfTimestamp);
        require(dayId > lastPerfAccrualDayId, "Deja provisionne");
        accruePerformanceFee();
        lastPerfAccrualDayId = dayId;
    }

    function ACCRUEDPERFFEE(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        uint256 dayId = _dayId(asOfTimestamp);
        require(dayId > lastPerfAccrualDayId, "Deja provisionne");
        accruePerformanceFee();
        lastPerfAccrualDayId = dayId;
    }

    function collectPerfFee(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        require(accruedPerformanceFeeUSD > 0, "Aucun frais de perf");
        require(_isYearEnd(asOfTimestamp), "Seulement fin d'annee");

        uint256 yearId = _yearId(asOfTimestamp);
        require(yearId > lastPerfFeeYear, "Deja collecte");

        uint256 feeUSD = accruedPerformanceFeeUSD;
        accruedPerformanceFeeUSD = 0;
        lastPerfFeeYear = yearId;
        lastPerfFeeTimestamp = block.timestamp;

        uint256 usdcAmount = _payoutUSD(feeUSD);
        highWaterMark = currentNavPerTokenUSD;
        emit PerformanceFeeCollected(feeUSD, usdcAmount, highWaterMark, yearId);
    }

    function COLLECTPERFFEE(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        require(accruedPerformanceFeeUSD > 0, "Aucun frais de perf");
        require(_isYearEnd(asOfTimestamp), "Seulement fin d'annee");

        uint256 yearId = _yearId(asOfTimestamp);
        require(yearId > lastPerfFeeYear, "Deja collecte");

        uint256 feeUSD = accruedPerformanceFeeUSD;
        accruedPerformanceFeeUSD = 0;
        lastPerfFeeYear = yearId;
        lastPerfFeeTimestamp = block.timestamp;

        uint256 usdcAmount = _payoutUSD(feeUSD);
        highWaterMark = currentNavPerTokenUSD;
        emit PerformanceFeeCollected(feeUSD, usdcAmount, highWaterMark, yearId);
    }

    // ========= Views =========
    function getHighWaterMark() external view returns (uint256) {
        return highWaterMark;
    }

    function getAccruedPerformanceFeeUSD() external view returns (uint256) {
        return accruedPerformanceFeeUSD;
    }

    function getCrystallizedPerformanceFeeUSD() external view returns (uint256) {
        return crystallizedPerformanceFeeUSD;
    }

    function getYearEndPerformanceFeeUSD() external view returns (uint256) {
        return yearEndPerformanceFeeUSD;
    }

    // ========= Perf fee internals =========
    function accruePerformanceFee() internal override {
        _accruePerformanceFeeForDay(_dayId(block.timestamp), currentNavPerTokenUSD);
    }

    function _accruePerformanceFeeForDay(uint256 dayId, uint256 navPerTokenBeforePerf) internal virtual override {
        if (dayId <= lastPerfAccrualDayId) return;
        uint256 supply = totalSupply();
        if (supply == 0) {
            accruedPerformanceFeeUSD = 0;
            highWaterMark = navPerTokenBeforePerf;
            lastPerfAccrualDayId = dayId;
            return;
        }

        if (navPerTokenBeforePerf <= highWaterMark) {
            // Excel-strict model: no pending perf fee when NAV is below/equal HWM.
            accruedPerformanceFeeUSD = 0;
            lastPerfAccrualDayId = dayId;
            return;
        }

        // Excel-strict model: daily provision is recomputed from scratch
        // against the current HWM (not cumulatively added day-over-day).
        uint256 navDiff = navPerTokenBeforePerf - highWaterMark;
        uint256 feePerToken = (navDiff * PERFORMANCE_FEE_BPS) / 10000;
        uint256 feeUSD = (feePerToken * supply) / 1e18;
        accruedPerformanceFeeUSD = feeUSD;
        lastPerfAccrualDayId = dayId;
    }

    function _onRedemptionCrystallizePerfFee(uint256 usdAmount18, uint256 totalValueUSD) internal virtual override {
        if (accruedPerformanceFeeUSD == 0 || usdAmount18 == 0 || totalValueUSD == 0) return;
        uint256 ratio = (usdAmount18 * 1e18) / (totalValueUSD * USD_TO_18);
        uint256 crystallized = (accruedPerformanceFeeUSD * ratio) / 1e18;
        if (crystallized == 0) return;
        if (crystallized > accruedPerformanceFeeUSD) crystallized = accruedPerformanceFeeUSD;
        accruedPerformanceFeeUSD -= crystallized;
        crystallizedPerformanceFeeUSD += crystallized;
    }
}
