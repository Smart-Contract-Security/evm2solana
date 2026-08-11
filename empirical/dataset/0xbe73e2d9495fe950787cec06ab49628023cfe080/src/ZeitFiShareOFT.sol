// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {OFT} from "@layerzerolabs/oapp-evm/oft/OFT.sol";

/// @title ZeitFiShareOFT
/// @notice Remote-chain wrapped share token for ZeitFi.
/// @dev Thin wrapper around LayerZero OFT with no custom bridge logic.
contract ZeitFiShareOFT is OFT {
    constructor(
        string memory name_,
        string memory symbol_,
        address endpoint_,
        address delegate_
    ) OFT(name_, symbol_, endpoint_, delegate_) {}
}
