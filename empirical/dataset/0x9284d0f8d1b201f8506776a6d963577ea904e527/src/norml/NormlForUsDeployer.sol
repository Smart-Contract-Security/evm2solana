// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NormlForUs} from "./NormlForUs.sol";

/// @title NormlForUsDeployer
/// @notice Standalone deployer for the (large) NormlForUs contract.
/// @dev    Exists solely so that `NormlGenesisOrchestrator` doesn't have to
///         embed NormlForUs's ~22KB initcode — which would push the
///         orchestrator past the 24KB EIP-170 deployed-code limit.
///
///         Flow:
///           1. Pre-flight: deploy this contract once (Ledger tx). No state risk.
///           2. Atomic tx: orchestrator calls `deploy(...)`. Newly-minted
///              NormlForUs is owned by this deployer for a single statement,
///              then ownership is transferred to the orchestrator (msg.sender).
///
///         This contract holds no state and is reusable.
contract NormlForUsDeployer {
    /// @notice Deploy a NormlForUs and transfer ownership to msg.sender.
    /// @dev    Caller (the orchestrator) becomes the owner; from there it can
    ///         call setRouter / mintWithInitialStake / transferOwnership to
    ///         the final Ledger EOA.
    function deploy(
        address liquidEdition,
        address assets,
        string calldata name_,
        string calldata symbol_,
        string calldata description_,
        string calldata externalUrl_
    ) external returns (address) {
        NormlForUs c = new NormlForUs(
            liquidEdition,
            assets,
            name_,
            symbol_,
            description_,
            externalUrl_
        );
        c.transferOwnership(msg.sender);
        return address(c);
    }
}
