// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEbisuAdminRegistry {
    function ebisuAdmin() external view returns (address);
    function transferEbisuAdmin(address _newEbisuAdmin) external;
}
