// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISymbiontNFT {
    function syncSymbionts(address wallet) external;
    function notifySell(address owner, uint256 oldBal, uint256 newBal) external;
    function getSymbiontCount(address wallet) external view returns (uint256);
    function getAverageHealth(address wallet) external view returns (uint256);
    function walletToTokenId(address wallet) external view returns (uint256);
    function autoMint(address to) external;
}
