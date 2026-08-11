// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokinsoCore.sol";

abstract contract TokinsoFeesModule is TokinsoCore {
    // ========= Admin functions =========
    function setFeeRecipient(address newRecipient) external onlyRole(BANK_ROLE) {
        require(newRecipient != address(0), "Zero address");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function setUsdcToken(address newToken) external onlyRole(BANK_ROLE) {
        require(newToken != address(0), "Zero address");
        usdcToken = newToken;
        emit UsdcTokenUpdated(newToken);
    }

    function accrueManagementFee(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        require(currentTotalValueUSD > 0, "NAV non definie");
        uint256 dayId = _dayId(asOfTimestamp);
        require(dayId > lastMgmtAccrualDayId, "Deja provisionne");

        _accrueManagementFeeForDay(dayId, currentTotalValueUSD, true);
    }

    function collectManagementFee(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        require(accruedManagementFeeUSD + crystallizedPerformanceFeeUSD > 0, "Aucun frais de gestion");
        uint256 dayId = _dayId(asOfTimestamp);
        require(dayId >= lastMgmtFeeDayId + MIN_DAYS_BETWEEN_MGMT_FEES, "Trop tot");

        uint256 feeUSD = accruedManagementFeeUSD + crystallizedPerformanceFeeUSD;
        accruedManagementFeeUSD = 0;
        crystallizedPerformanceFeeUSD = 0;
        lastMgmtFeeDayId = dayId;

        uint256 usdcAmount = _payoutUSD(feeUSD);
        emit ManagementFeeCollected(feeUSD, usdcAmount, dayId);
    }

    function collectYearEndPerformanceFee(uint256 asOfTimestamp) external onlyRole(FEE_MANAGER_ROLE) {
        require(yearEndPerformanceFeeUSD > 0, "Aucun frais de perf");
        uint256 feeUSD = yearEndPerformanceFeeUSD;
        yearEndPerformanceFeeUSD = 0;
        uint256 usdcAmount = _payoutUSD(feeUSD);
        emit PerformanceFeeCollected(feeUSD, usdcAmount, highWaterMark, _yearId(asOfTimestamp));
    }

    // ========= Views =========
    function getAccruedManagementFeeUSD() external view returns (uint256) {
        return accruedManagementFeeUSD;
    }
}
