// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPawnTreasury {
    function receiveETH() external payable;
    function onNFTMint(address holder, uint8 tier) external;
    function onNFTBurn(address holder, uint8 tier, bool isSell) external;
    function settleHolder(address holder) external;
    function treasuryActive() external view returns (bool);
}
