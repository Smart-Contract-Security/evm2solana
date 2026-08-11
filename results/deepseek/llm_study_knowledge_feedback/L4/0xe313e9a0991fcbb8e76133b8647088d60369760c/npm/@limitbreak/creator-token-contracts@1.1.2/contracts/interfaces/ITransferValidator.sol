// SPDX-License-Identifier: MIT

import "../utils/TransferPolicy.sol";

interface ITransferValidator {
    function applyCollectionTransferPolicy(address caller, address from, address to) external view;
}