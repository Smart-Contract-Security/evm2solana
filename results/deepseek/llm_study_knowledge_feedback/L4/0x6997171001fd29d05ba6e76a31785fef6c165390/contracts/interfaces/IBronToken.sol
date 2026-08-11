// SPDX-License-Identifier: MIT

import 'solana';

interface IBronToken {
    function loyaltyLock(address account, uint64 value) external;

    function loyaltyUnlock(address account, uint64 value) external;

    function availableBalanceOf(address account) external view returns (uint64);

    function loyaltyLockedBalanceOf(address account) external view returns (uint64);
}