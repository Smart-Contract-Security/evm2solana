// SPDX-License-Identifier: MIT

import 'solana';

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint64);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transfer(address to, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}