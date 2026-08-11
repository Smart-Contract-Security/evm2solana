// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWhitelist {
    function isWhitelisted(address account) external view returns (bool);
    function isAssetAllowed(address asset) external view returns (bool);
}
