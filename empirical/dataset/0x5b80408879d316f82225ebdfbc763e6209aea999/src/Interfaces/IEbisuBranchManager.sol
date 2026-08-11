// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import "../Types/LatestTroveData.sol";
import "../Types/LatestBatchData.sol";
import "./ILiquityBase.sol";

enum Parameter {
    MCR,
    MIN_ANNUAL_INTEREST_RATE,
    SP_YIELD_SPLIT,
    DEBT_CAP,
    PAUSE_MINTING,
    UNPAUSE_MINTING,
    FINALIZE_PARAMETER,
    REDEMPTION_FEE_FLOOR,
    CCR,
    MIN_DEBT,
    BRANCH_COLL_GAS_COMPENSATION_CAP
}

interface IEbisuBranchManager is ILiquityBase {
    struct SingleRedemptionValues {
        uint256 troveId;
        address batchAddress;
        uint256 boldLot;
        uint256 collLot;
        uint256 collFee;
        uint256 appliedRedistBoldDebtGain;
        uint256 oldWeightedRecordedDebt;
        uint256 newWeightedRecordedDebt;
        uint256 newStake;
        bool isZombieTrove;
        LatestTroveData trove;
        LatestBatchData batch;
    }

    function initialize(address _addressesRegistryAddress) external;

    function MCR() external view returns (uint256);

    function CCR() external view returns (uint256);

    function SCR() external view returns (uint256);

    function liquidationPenaltySp() external view returns (uint256);

    function liquidationPenaltyRedistribution() external view returns (uint256);

    function mintingDebtAllowed() external view returns (bool);

    function spYieldSplit() external view returns (uint256);

    function debtCap() external view returns (uint256);

    function minDebt() external view returns (uint256);

    function branchCollGasCompensationCap() external view returns (uint256);

    function requireValidAnnualInterestRate(uint256 _annualInterestRate) external view;

    function getOffsetAndRedistributionVals(
        uint256 _entireTroveDebt,
        uint256 _collToLiquidate, // gas compensation is already subtracted
        uint256 _boldInStabPool,
        uint256 _price
    )
        external
        view
        returns (
            uint256 debtToOffset,
            uint256 collToSendToSP,
            uint256 collGasCompensation,
            uint256 debtToRedistribute,
            uint256 collToRedistribute,
            uint256 collSurplus
        );

    function pauseMintingDebt() external;

    function unpauseMintingDebt() external;

    function setParameterController(Parameter parameter, address controller, bool isAuthorized) external;

    function isAuthorizedAddress(Parameter parameter, address controller) external view returns (bool);

    function setSpYieldSplit(uint256 _spYieldSplit) external;

    function finalizeParameterChange(Parameter parameter) external;

    function setMCR(uint256 _MCR) external;

    function setCCR(uint256 _CCR) external;

    function setDebtCap(uint256 _debtCap) external;

    function setBranchRedemptionFeeFloor(uint256 _redemptionFeeFloor) external;

    function setDebtCapAndRedemptionFeeFloor(uint256 _debtCap, uint256 _redemptionFeeFloor) external;

    function getTroveMinAnnualInterestRate() external view returns (uint256);

    function setInterestRouter(address _interestRouter) external;

    function cancelParameterProposal(Parameter parameter) external;

    function setMinDebt(uint256 _minDebt) external;

    function setBranchCollGasCompensationCap(uint256 _branchCollGasCompensationCap) external;

    function redeemCollateral(
        address _redeemer,
        uint256 _boldamount,
        uint256 _price,
        uint256 _redemptionRate,
        uint256 _maxIterations
    ) external returns (uint256 _redemeedAmount);

    function urgentRedemption(uint256 _boldamount, uint256[] memory _troveIds, uint256 _totalCollRedeemed) external;

    function getUnbackedPortionPriceAndRedeemability() external returns (uint256, uint256, bool);

    function shutdown() external;

    function shutdownTime() external view returns (uint256);

    function totalDebtTaken() external view returns (uint256);
}
