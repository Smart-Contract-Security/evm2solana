// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.5.0;

/// @title IDepositContract - Ethereum beacon chain deposit contract interface
/// @notice Standard interface for interacting with the official ETH2 deposit contract
///         to activate validators and top up existing ones.
interface IDepositContract {
    /// @notice Returns the current deposit Merkle tree root hash
    /// @return rootHash The root of the deposit Merkle tree
    function get_deposit_root() external view returns (bytes32 rootHash);

    /// @notice Returns the current deposit count
    /// @return count The deposit count encoded as a little-endian 64-bit number
    function get_deposit_count() external view returns (bytes memory count);

    /// @notice Submit a deposit to the beacon chain
    /// @dev msg.value is the deposit amount in wei. 32 ETH required for new validator activation.
    /// @param pubkey Validator BLS public key (48 bytes)
    /// @param withdrawal_credentials Withdrawal credentials (32 bytes), 0x02-type points to vault address
    /// @param signature BLS signature over DepositMessage(pubkey, wc, amount) (96 bytes)
    /// @param deposit_data_root SSZ hash tree root of the deposit data for integrity verification
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable;
}
