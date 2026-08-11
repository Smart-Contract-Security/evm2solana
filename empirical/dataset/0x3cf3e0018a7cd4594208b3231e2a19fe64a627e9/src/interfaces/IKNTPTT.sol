// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKNTPTT {
    error KNTPTT__TransfersDisallowed();

    function initialize(address _admin, address _minter, address _burner) external;
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    function getMinterRole() external pure returns (bytes32);
    function getBurnerRole() external pure returns (bytes32);
}
