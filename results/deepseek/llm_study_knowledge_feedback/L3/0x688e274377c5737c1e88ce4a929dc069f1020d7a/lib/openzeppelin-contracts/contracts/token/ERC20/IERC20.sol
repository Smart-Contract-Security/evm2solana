// SPDX-License-Identifier: MIT

interface IERC20 {
    event Transfer(address from, address to, uint64 value);
    event Approval(address owner, address spender, uint64 value);

    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}