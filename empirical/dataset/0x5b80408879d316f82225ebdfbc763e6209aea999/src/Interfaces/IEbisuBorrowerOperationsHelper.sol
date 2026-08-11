// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IBorrowerOperations.sol";
import "./IPriceFeed.sol";
import "../Dependencies/BoStructs.sol";
import "./ILiquityBase.sol";
import "../Types/LatestTroveData.sol";
import "../Types/LatestBatchData.sol";

interface IEbisuBorrowerOperationsHelper is ILiquityBase {
    function initialize(address _addressesRegistryAddress) external;

    function initSetInterestIndividualDelegate(
        address caller,
        uint256 _troveId,
        address _delegate,
        uint128 _minInterestRate,
        uint128 _maxInterestRate,
        uint256 _minInterestRateChangePeriod
    ) external;

    function getInterestBatchManager(address _account) external view returns (InterestBatchManager memory);
    function checkBatchManagerExists(address _batchManager) external view returns (bool);
    function requireValidInterestBatchManager(address _interestBatchManagerAddress) external view;

    function initCloseTrove(address caller, uint256 _troveId, address batchManager)
        external
        returns (LatestTroveData memory);

    function initAdjustTroveInterestRate(
        address caller,
        uint256 _troveId,
        uint256 _newAnnualInterestRate,
        uint256 _maxUpfrontFee,
        uint256 _upperHint,
        uint256 _lowerHint
    ) external returns (TroveChange memory troveChange, LatestTroveData memory trove, uint256 newDebt);

    function initAdjustTrove(
        uint256 _troveId,
        address caller,
        LocalVariables_adjustTrove memory vars,
        TroveChange memory _troveChange,
        uint256 _maxUpfrontFee,
        address batchManager
    ) external returns (LocalVariables_adjustTrove memory, TroveChange memory);

    function applyUpfrontFee(
        uint256 _troveEntireColl,
        uint256 _troveEntireDebt,
        TroveChange memory _troveChange,
        uint256 _maxUpfrontFee,
        bool _isTroveInBatch
    ) external returns (uint256, TroveChange memory);

    function removeInterestIndividualDelegate(uint256 _troveId) external;

    function getInterestIndividualDelegateOf(uint256 _troveId)
        external
        view
        returns (InterestIndividualDelegate memory);

    function setInterestBatchManager(
        uint256 _troveId,
        address _newBatchManager,
        uint256 _upperHint,
        uint256 _lowerHint,
        uint256 _maxUpfrontFee
    ) external;

    function setInterestBatchManager(
        address caller,
        uint256 _troveId,
        address _newBatchManager,
        uint256 _upperHint,
        uint256 _lowerHint,
        uint256 _maxUpfrontFee
    ) external;

    function initSwitchBatchManager(uint256 _troveId, address _newBatchManager)
        external
        returns (LatestBatchData memory);

    function registerBatchManager(
        uint128 minInterestRate,
        uint128 maxInterestRate,
        uint128 currentInterestRate,
        uint128 fee,
        uint128 minInterestRateChangePeriod
    ) external;

    function setBatchManagerAnnualInterestRate(
        uint128 _newAnnualInterestRate,
        uint256 _upperHint,
        uint256 _lowerHint,
        uint256 _maxUpfrontFee
    ) external;

    function lowerBatchManagementFee(address _caller, uint256 _newAnnualManagementFee) external;

    function setMinDebt(uint256 _minDebt) external;
}
