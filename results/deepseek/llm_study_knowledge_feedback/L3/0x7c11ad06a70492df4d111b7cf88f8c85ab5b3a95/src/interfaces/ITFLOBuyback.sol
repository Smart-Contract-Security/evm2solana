// SPDX-License-Identifier: MIT

import 'solana';

interface ITFLOBuyback {
    @account(sysvarClock)
    function buyAndBurn(uint64 minOut) external;
}