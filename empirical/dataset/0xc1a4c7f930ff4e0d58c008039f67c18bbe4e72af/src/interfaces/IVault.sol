// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVault {
    enum WithdrawStatus {
        None,
        Open,
        Claimed,
        Cancelled,
        Settled
    }

    enum DepositStatus {
        None,
        Pending,
        Settled,
        Cancelled
    }

    struct WithdrawRequest {
        address owner;
        uint256 shares;
        uint256 costBasisValueSnapshot;
        uint64 requestedAt;
        uint64 claimableAt;
        WithdrawStatus status;
        uint256 assetsOut;
        uint256 fee;
    }

    struct DepositRequest {
        address owner;
        uint256 assets;
        DepositStatus status;
    }

    // ── Deposit events ───────────────────────────────────────────────
    event DepositRequested(uint256 indexed depositId, address indexed owner, uint256 assets);
    event DepositSettled(uint256 indexed depositId, address indexed owner, uint256 netAssets, uint256 shares);
    event DepositCancelled(uint256 indexed depositId, address indexed owner, uint256 assets);
    event DepositAutoRefunded(uint256 indexed depositId, address indexed owner, uint256 assets);

    // ── Withdraw events ──────────────────────────────────────────────
    event WithdrawRequested(
        uint256 indexed requestId, address indexed owner, uint256 shares, uint64 claimableAt
    );
    event WithdrawalSettled(
        uint256 indexed requestId,
        address indexed owner,
        uint256 shares,
        uint256 assetsOut,
        uint256 fee
    );
    event WithdrawClaimed(
        uint256 indexed requestId, address indexed owner, uint256 shares, uint256 assetsPaid, uint256 fee
    );
    event WithdrawCancelled(uint256 indexed requestId, address indexed owner, uint256 shares);

    // ── Settlement / rebalance events ────────────────────────────────
    event Settled(
        uint256 oraclePriceCount,
        uint256 depositsSettled,
        uint256 depositsRefunded,
        uint256 withdrawalsProcessed
    );
    event Rebalanced(uint256 callCount, uint256 navBefore, uint256 navAfter);

    // ── Config events ────────────────────────────────────────────────
    event TrackedTokenAdded(address indexed token);
    event TrackedTokenRemoved(address indexed token);
    event PerformanceFeeSet(uint256 feeBps);
    event SettlementFeeSet(uint256 fee);
    event MinDepositAssetsSet(uint256 amount);
    event MaxSettlementBatchSizeSet(uint256 size);
    event OracleSet(address indexed oracle);
    event TargetAllowed(address indexed target, bool allowed);

    // ── Errors ───────────────────────────────────────────────────────
    error ZeroAmount();
    error InvalidFee();
    error AlreadyTracked();
    error NotTracked();
    error TrackedTokenHasBalance(address token, uint256 balance);
    error NotRequestOwner();
    error RequestNotOpen();
    error WithdrawNotReady();
    error InsufficientLiquidity();
    error InsufficientShares();
    error TargetNotAllowed(address target);
    error OnlyHPT();
    error DepositTooSmall();
    error InvalidBatchSize();

    function asset() external view returns (address);
    function shares() external view returns (address);
    function oracle() external view returns (address);

    function totalAssets() external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function costBasisPerShare(address user) external view returns (uint256);

    function requestDeposit(uint256 assets) external returns (uint256 depositId);
    function requestDepositFor(uint256 assets, address recipient) external returns (uint256 depositId);
    function cancelDepositRequest(uint256 depositId) external;
    function cancelPendingDeposits(uint256 maxCount) external returns (uint256 cancelled);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 sharesIn, address owner)
        external
        view
        returns (uint256 estimatedAssets, uint256 estimatedFee);
    function requestWithdraw(uint256 sharesIn) external returns (uint256 requestId);
    function claimWithdraw(uint256 requestId) external;
    function claimWithdrawTo(uint256 requestId, address recipient) external;
    function claimAndDeposit(uint256 requestId, IVault newVault) external returns (uint256 depositId);
    function cancelWithdraw(uint256 requestId) external;

    function settle(address[] calldata tokens, uint128[] calldata prices) external;
    function hasSettleReadyWork() external view returns (bool);

    function rebalance(address[] calldata targets, bytes[] calldata calldatas) external;

    function onShareTransfer(address from, address to, uint256 value) external;

    function pendingWithdrawShares() external view returns (uint256);
    function pendingSettlementWithdrawShares() external view returns (uint256);
    function pendingDepositTotal() external view returns (uint256);
    function settledWithdrawalLiabilityTotal() external view returns (uint256);
    function settlementFeeAssets() external view returns (uint256);
    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory);
    function getDepositRequest(uint256 depositId) external view returns (DepositRequest memory);
    function userDepositIds(address user) external view returns (uint256[] memory);

    function setMinDepositAssets(uint256 amount) external;
    function setMaxSettlementBatchSize(uint256 size) external;
    function setSettlementFee(uint256 fee) external;
}
