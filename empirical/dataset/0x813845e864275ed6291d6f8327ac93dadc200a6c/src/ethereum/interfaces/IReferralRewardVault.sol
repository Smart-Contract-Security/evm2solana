// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Ethereum Mainnet CLGO Merkle distributor interface.
interface IReferralRewardVault {
    event RootUpdated(uint256 indexed weekId, bytes32 root);
    event Claimed(address indexed user, uint256 amount, uint256 cumulativeAfter);

    error InvalidWeekId();
    error ZeroRoot();
    error InvalidProof();
    error InsufficientVaultBalance();

    function currentRoot() external view returns (bytes32);
    function currentWeekId() external view returns (uint256);
    function claimed(address user) external view returns (uint256);

    /// @notice Distributor posts a new cumulative Merkle root (weekId must increment by 1)
    function setRoot(uint256 weekId, bytes32 root) external;

    /// @notice Claim CLGO up to cumulativeAmount; sends only the unclaimed delta
    function claim(uint256 cumulativeAmount, bytes32[] calldata proof) external;

    /// @notice View how much a user can claim right now
    function pendingFor(address user, uint256 cumulativeAmount, bytes32[] calldata proof)
        external view returns (uint256);

    /// @notice Admin-only emergency withdrawal
    function emergencyWithdraw(address to, uint256 amount) external;
}
