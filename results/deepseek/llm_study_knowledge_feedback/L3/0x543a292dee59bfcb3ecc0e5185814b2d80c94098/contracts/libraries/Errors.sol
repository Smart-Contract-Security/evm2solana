// SPDX-License-Identifier: MIT

/// @title Errors
/// @notice Centralized custom errors for Apyee contracts (gas-efficient over require strings).
/// @dev Pause-related errors come from OpenZeppelin Pausable (EnforcedPause / ExpectedPause).
library Errors {
    // --- Access ---
    // Note: Error definitions are not yet supported on Solana.
    // Using revert with string messages instead.

    // --- Access ---
    function NotOwner() internal pure {
        revert("NotOwner");
    }

    function NotKeeper() internal pure {
        revert("NotKeeper");
    }

    function NotGuardian() internal pure {
        revert("NotGuardian");
    }

    function NotVault() internal pure {
        revert("NotVault");
    }

    // --- Config ---
    function ZeroAddress() internal pure {
        revert("ZeroAddress");
    }

    function ZeroAmount() internal pure {
        revert("ZeroAmount");
    }

    function FeeTooHigh(uint64 requested, uint64 max) internal pure {
        revert("FeeTooHigh");
    }

    function InvalidAllocation(uint64 totalBps) internal pure {
        revert("InvalidAllocation");
    }

    // --- Vault ---
    function DepositCapReached(uint64 requested, uint64 cap) internal pure {
        revert("DepositCapReached");
    }

    function UserCapExceeded(uint64 cap, uint64 attempted) internal pure {
        revert("UserCapExceeded");
    }

    function WithdrawalExceedsBalance(uint64 requested, uint64 available) internal pure {
        revert("WithdrawalExceedsBalance");
    }

    function IdleInsufficient(uint64 requested, uint64 available) internal pure {
        revert("IdleInsufficient");
    }

    // --- Strategy ---
    function StrategyNotWhitelisted(address strategy) internal pure {
        revert("StrategyNotWhitelisted");
    }

    function StrategyAlreadyAdded(address strategy) internal pure {
        revert("StrategyAlreadyAdded");
    }

    function StrategyHasBalance(address strategy, uint64 balance) internal pure {
        revert("StrategyHasBalance");
    }

    function StrategyBlacklisted(address strategy) internal pure {
        revert("StrategyBlacklisted");
    }

    function BlacklistCooldownActive(uint64 remaining) internal pure {
        revert("BlacklistCooldownActive");
    }

    function AssetMismatch(address expected, address actual) internal pure {
        revert("AssetMismatch");
    }

    function ProtocolCallFailed(uint64 errorCode) internal pure {
        revert("ProtocolCallFailed");
    }

    // --- Allocation ---
    function AllocationExceeded(uint64 requested, uint64 max) internal pure {
        revert("AllocationExceeded");
    }
}