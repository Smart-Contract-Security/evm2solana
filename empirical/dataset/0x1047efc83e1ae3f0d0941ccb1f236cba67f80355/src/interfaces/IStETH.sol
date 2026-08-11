// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStETH {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function submit(address _referral) external payable returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    // burn 기능이 필요하다면 아래 주석 해제 (MockStETH에 burn 함수가 있어야 함)
    // function burn(uint256 amount) external;
}