// SPDX-License-Identifier: MIT OR Apache-2.0

import 'solana';

contract Indexed {
    uint64 public immutable deployedBlock;

    @payer(payer)
    @space(24)
    constructor(address payer) {
        deployedBlock = block.number;
    }
}