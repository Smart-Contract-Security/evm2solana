// SPDX-License-Identifier: MIT

import 'solana';

interface IERC20 {
    function totalSupply() external view returns (uint64);

    function balanceOf(address account) external view returns (uint64);

    function transfer(address recipient, uint64 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint64);

    function approve(address spender, uint64 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);

    event Transfer(address from, address to, uint64 value);

    event Approval(address owner, address spender, uint64 value);
}