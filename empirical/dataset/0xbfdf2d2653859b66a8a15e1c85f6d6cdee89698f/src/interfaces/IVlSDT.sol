// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IVlSDT {
    function SDT() external view returns (address);
    function BOOST_REGISTRY() external view returns (address);
    function stake(uint256 amount, address recipient) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
