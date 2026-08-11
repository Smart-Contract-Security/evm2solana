// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenFactory {
    event TokenCreated(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        uint256 supply
    );

    function LAUNCH_FEE() external view returns (uint256);
    function ect() external view returns (address);
    function treasury() external view returns (address);
    function registry() external view returns (address);
    function pairFactory() external view returns (address);

    function createToken(string calldata name, string calldata symbol, uint256 supply)
        external
        returns (address token);
}
