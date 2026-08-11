// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IBoldToken.sol";
import {ITroveManager} from "./ITroveManager.sol";
import "./IEbisuAdminRegistry.sol";
import "./IEbisuBranchManager.sol";
import "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ICollateralRegistry is IEbisuAdminRegistry {
    function baseRate() external view returns (uint256);
    function lastFeeOperationTime() external view returns (uint256);

    function redeemCollateral(uint256 _boldamount, uint256 _maxIterations, uint256 _maxFeePercentage) external;
    // getters
    function totalCollaterals() external view returns (uint256);
    function getToken(uint256 _index) external view returns (IERC20Metadata);
    function getTroveManager(uint256 _index) external view returns (ITroveManager);
    function getBranchManager(address _token) external view returns (IEbisuBranchManager);
    function getBranchManager(uint256 _index) external view returns (IEbisuBranchManager);
    function boldToken() external view returns (IBoldToken);
    function branchFactoryAddress() external view returns (address);
    function troveManagerAddresses(address _address) external view returns (bool);
    function branchManagerAddresses(address _address) external view returns (bool);
    function stabilityPoolAddresses(address _address) external view returns (bool);
    function borrowerOperationsAddresses(address _address) external view returns (bool);
    function activePoolAddresses(address _address) external view returns (bool);

    function getRedemptionRate() external view returns (uint256);
    function getRedemptionRateWithDecay() external view returns (uint256);
    function getBranchRedemptionRate(uint256 _index) external view returns (uint256);
    function getBranchRedemptionRateWithDecay(uint256 _index) external view returns (uint256);
    function getRedemptionRateForRedeemedAmount(uint256 _redeemAmount) external view returns (uint256);

    function getRedemptionFeeWithDecay(uint256 _ETHDrawn) external view returns (uint256);
    function getEffectiveRedemptionFeeInBold(uint256 _redeemAmount) external view returns (uint256);
    function getTokenIndex(address _token) external view returns (uint256);
    function redemptionFeeFloors(uint256 _index) external view returns (uint256);

    // add branches
    function addNewBranch(
        address _token,
        ITroveManager _troveManager,
        address _stabilityPoolAddress,
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        IEbisuBranchManager _branchManager
    ) external;

    function setBranchRedemptionFeeFloor(address _token, uint256 _redemptionFeeFloor) external;

    function getHighestRedemptionRateWithDecay() external view returns (uint256);
    function getTotalSystemDebt() external view returns (uint256);

    function setBranchFactory(address _branchFactory) external;
}
