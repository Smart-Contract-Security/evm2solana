// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPlanetDispenser {
    function redeemPlanet(uint32 planetId, address recipient, address _managementProxy) external;
    function priceAndAllowance(
        address buyer
    ) external view returns (uint256 price, uint256 allowance, uint256 balance);
    function urbitToken() external view returns (address);
}
