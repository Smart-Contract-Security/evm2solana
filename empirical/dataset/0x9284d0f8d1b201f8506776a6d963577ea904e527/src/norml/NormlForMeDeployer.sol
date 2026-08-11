// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NormlForMe} from "./NormlForMe.sol";

/// @title NormlForMeDeployer
/// @notice Standalone deployer for the (large) NormlForMe contract.
/// @dev    Exists solely so that `NormlGenesisOrchestrator` doesn't have to
///         embed NormlForMe's initcode — which would push the orchestrator
///         past the 24,576-byte EIP-170 deployed-code limit.
///
///         Flow:
///           1. Pre-flight: deploy this contract once (Ledger tx). No state risk.
///           2. Atomic tx: orchestrator calls `deploy(...)`. Newly-minted
///              NormlForMe is owned by this deployer for a single statement,
///              then ownership is transferred to the orchestrator (msg.sender).
///
///         This contract holds no state and is reusable.
///
/// @dev    Side-effect note: NormlForMe's constructor sets
///         `royaltyReceiver = msg.sender`, so post-deploy the royalty receiver
///         is this deployer contract (inert). The orchestrator transfers
///         ownership to the Ledger creator at the end of `execute()`, and the
///         creator can then call `setRoyalty(...)` to point royalties at the
///         desired receiver. This matches the prior behavior where the
///         orchestrator itself was the initial royaltyReceiver.
contract NormlForMeDeployer {
    /// @notice Deploy a NormlForMe and transfer ownership to msg.sender.
    /// @dev    Caller (the orchestrator) becomes the owner; from there it can
    ///         call setRouter / transferOwnership to the final Ledger EOA.
    function deploy(
        address normlToken,
        string calldata name_,
        string calldata symbol_,
        string calldata description_,
        string calldata externalUrl_
    ) external returns (address) {
        NormlForMe c = new NormlForMe(
            normlToken,
            name_,
            symbol_,
            description_,
            externalUrl_
        );
        c.transferOwnership(msg.sender);
        return address(c);
    }
}
