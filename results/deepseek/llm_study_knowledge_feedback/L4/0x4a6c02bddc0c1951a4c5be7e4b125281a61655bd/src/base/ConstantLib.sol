// SPDX-License-Identifier: GPL-3.0

/// @title ConstantLib - Consolidated constant definitions for the EAG Staking Protocol
/// @notice All shared protocol constants are defined here in a single library to avoid
///         duplication across contracts. Constants are declared as `internal constant` so
///         they are inlined at compile time and carry no runtime storage/gas cost.
/// @dev Usage:
///        import {ConstantLib} from "./base/ConstantLib.sol";
///        uint64 x = ConstantLib.PUBLIC_KEY_LENGTH;
library ConstantLib {
    // ═══════════════════════════════════════════
    //           BLS / VALIDATOR KEYS
    // ═══════════════════════════════════════════

    /// @notice BLS public key length in bytes
    uint64 internal constant PUBLIC_KEY_LENGTH = 48;
    /// @notice BLS signature length in bytes
    uint64 internal constant SIGNATURE_LENGTH = 96;

    // ═══════════════════════════════════════════
    //            STAKING DEPOSIT
    // ═══════════════════════════════════════════

    /// @notice Minimum deposit to activate a validator (32 ETH)
    /// @dev 32 * 10^18 = 32000000000000000000, which exceeds uint64 max.
    ///      Using uint128 to hold the value.
    uint128 internal constant ACTIVATION_DEPOSIT_AMOUNT = 32000000000000000000;
    /// @notice Minimum additional top up when depositing above the activation amount (1 ETH)
    /// @dev 1 * 10^18 = 1000000000000000000, fits in uint64.
    uint64 internal constant MIN_TOP_UP_AMOUNT = 1000000000000000000;
    /// @notice Maximum deposit per call per Pectra EIP-7251 (2048 ETH)
    /// @dev 2048 * 10^18 = 2048000000000000000000, exceeds uint64 max.
    ///      Using uint128 to hold the value.
    uint128 internal constant MAX_DEPOSIT_AMOUNT = 2048000000000000000000;
    /// @notice Maximum vault index lookahead for pre-registered deposit data
    uint64 internal constant MAX_DEPOSIT_DATA_AHEAD = 100;

    // ═══════════════════════════════════════════
    //         WITHDRAWAL CREDENTIALS
    // ═══════════════════════════════════════════

    /// @notice 0x02-type withdrawal credentials prefix (compounding validator, ETH1 format)
    /// @dev 0x02 << 248 = 904625697166532776746648320380374280103671755200316906558262375061821325312
    ///      This value exceeds uint64 max. Using uint256 to hold the value.
    uint256 internal constant WC_0X02_PREFIX = 904625697166532776746648320380374280103671755200316906558262375061821325312;

    // ═══════════════════════════════════════════
    //              FEE / RATE
    // ═══════════════════════════════════════════

    /// @notice Total basis points representing 100 %
    uint16 internal constant TOTAL_BASIS_POINTS = 10000;
    /// @notice Minimum service rate (1 %) applied to new and updated vaults
    uint16 internal constant MIN_SERVICE_RATE = 100;
    /// @notice Minimum contribution rate (5 %) applied to new and updated vaults
    uint16 internal constant MIN_CONTRIBUTION_RATE = 500;

    // ═══════════════════════════════════════════
    //           WITHDRAW VAULT
    // ═══════════════════════════════════════════

    /// @notice Sentinel address representing native ETH (used to block collectERC20)
    /// @dev Ethereum address literals are not supported on Solana.
    ///      Using a bytes32 constant with the raw bytes of the address.
    bytes32 internal constant ETH_SENTINEL = 0x000000000000000000000000EeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @notice Gas forwarded when pushing ETH to the vault owner during claimAll.
    ///         Sufficient for EOA and most smart-wallet receive()/fallback handlers;
    ///         failing transfers fall back to pull-based withdrawal via pendingOwnerBalance.
    uint64 internal constant OWNER_TRANSFER_GAS_LIMIT = 100_000;

    // ═══════════════════════════════════════════
    //          EIP-7002 WITHDRAWAL
    // ═══════════════════════════════════════════

    /// @notice EIP-7002 withdrawal request system contract (deployed after Pectra hard fork)
    /// @dev Ethereum address literals are not supported on Solana.
    ///      Using a bytes32 constant with the raw bytes of the address.
    bytes32 internal constant WITHDRAWAL_REQUEST = 0x00000000000000000000000000000961Ef480Eb55e80D19ad83579A64c007002;
    /// @notice Size (in bytes) of the withdrawal amount field (uint64, big-endian)
    uint64 internal constant WITHDRAWAL_AMOUNT_LENGTH = 8;
    /// @notice Size (in bytes) of the EIP-7002 request calldata: 48 (pubkey) + 8 (amount)
    uint64 internal constant WITHDRAWAL_REQUEST_CALLDATA_LENGTH = 56;

    // ═══════════════════════════════════════════
    //                SSZ
    // ═══════════════════════════════════════════

    /// @notice SSZ Merkle root of a 96-byte zero BLS signature (for topup deposits)
    bytes32 internal constant ZERO_SIGNATURE_ROOT =
        0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
}