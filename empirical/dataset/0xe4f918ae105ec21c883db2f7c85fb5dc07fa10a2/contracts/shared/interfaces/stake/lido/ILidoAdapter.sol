// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDeFiAdapter} from "../../../../shared/interfaces/IDeFiAdapter.sol";

/// @title ILidoAdapter
/// @notice Lido protocol adapter interface.
///
/// Version mapping per PoolType:
///
///   PoolType.Staked:
///     version 1 — stETH  (rebase, sharesOf → getPooledEthByShares)
///     version 2 — wstETH (wrapped, balanceOf → getStETHByWstETH)
///     version 3 — CSAccounting (community-staking bond, needs nodeOperatorId from backend)
///
///   PoolType.Deposit:
///     version 1 — WithdrawalQueue unstETH NFT (ERC-721)
///
///   PoolType.Yield:
///     version 1 — strETH / stRATEGY (Mellow DepositQueue + Vault)
///     version 2 — GG Token / GGV    (Veda BoringVault + Accountant)
///     version 3 — earnETH           (Mellow ShareManager, asset = wstETH)
///     version 4 — earnUSD           (Mellow ShareManager, asset = USDC)
///
///   PoolType.Locked:
///     version 1 — strETH DepositQueue pending deposit (~24 h delay)
interface ILidoAdapter is IDeFiAdapter {

    struct PoolConfig {
        address pool;           // Pool main contract address
        PoolType poolType;      // IDeFiAdapter.PoolType (Staked / Deposit / Yield / Locked)
        bool enabled;           // Whether enabled
        int8 version;           // Sub-type version within the same poolType (see mapping above)
    }

    /// @notice Batch add pools with full config
    function addPools(PoolConfig[] calldata configs) external;

    /// @notice Get all pool configurations
    function getAllPoolConfigs() external view returns (PoolConfig[] memory);

    /// @notice Get pool configuration by poolId
    function getPoolConfig(bytes32 poolId) external view returns (PoolConfig memory);

    /// @notice Get pool configuration by index
    function getPoolConfigByIndex(uint256 index) external view returns (PoolConfig memory);

    /// @notice Get total pool count
    function getPoolConfigsLength() external view returns (uint256);
}

// ============ External Protocol Interfaces ============

/// @notice Lido stETH — 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
interface ILido {
    function getTotalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function sharesOf(address _account) external view returns (uint256);
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function token() external view returns (address);
    function convertStMaticToMatic(uint256 _amountInStMatic) external view returns (uint256,uint256,uint256);
    
}

/// @notice Wrapped stETH — 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
interface IWstETH {
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function stEthPerToken() external view returns (uint256);
    function tokensPerStEth() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Community Staking Module Accounting — 0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da
interface ICSAccounting {
    function getBondSummary(uint256 nodeOperatorId)
        external
        view
        returns (uint256 current, uint256 required);
}

/// @notice Lido WithdrawalQueue ERC721 — 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1
interface IWithdrawalQueueERC721 {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }


    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestIds);
    function getWithdrawalStatus(uint256[] memory _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function getClaimableEther(uint256[] memory _requestIds, uint256[] memory _hints)
        external
        view
        returns (uint256[] memory claimableEthValues);
    function findCheckpointHints(uint256[] memory _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds);
    function getOwnedTokens(address _owner) external view returns (uint256[] memory requestIds);
    function getMaticFromTokenId(uint256 _requestIds)
        external
        view
        returns (uint256);
    function getLockedEtherAmount() external view returns (uint256);
    function unfinalizedStETH() external view returns (uint256);
    function getLastRequestId() external view returns (uint256);
    function getLastFinalizedRequestId() external view returns (uint256);
}

/// @notice Mellow DepositQueue (strETH entry) — 0xcd3c0f51798d1daa92fb192e57844ae6cee8a6c7
interface IMellowDepositQueue {
    /// @notice Per-request entry returned by requestsOf().
    struct Request {
        /// @notice Timestamp when the redemption request was submitted.
        uint256 timestamp;
        /// @notice Amount of vault shares submitted for redemption.
        uint256 shares;
        /// @notice Whether the request has been processed and is now claimable.
        bool isClaimable;
        /// @notice Amount of assets that can be claimed by the user (set after handleReport).
        uint256 assets;
    }

    function requestsOf(address account, uint256 offset, uint256 limit)
        external
        view
        returns (Request[] memory requests);
    function asset() external view returns (address);
    function oracle() external view returns (address);
    function vault() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function getReport(address asset) external view returns (uint224, uint32, bool);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function depositInterval() external view returns (uint256);
}

interface IMellowVault {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Veda Accountant (GGV rate provider)
interface IVedaAccountant {
    function getRate() external view returns (uint256);
    function getRateSafe() external view returns (uint256);
}

/// @notice Veda BoringQueue (GGV withdrawal queue)
interface IVedaBoringQueue {
    struct WithdrawRequest {
        address user;
        address assetOut;
        uint96 amountOfShares;
        uint96 discount;
        uint32 secondsToDeadline;
        uint256 creationTime;
    }

    function getWithdrawRequest(bytes32 requestId) external view returns (WithdrawRequest memory);
    function getUserWithdrawRequests(address user) external view returns (bytes32[] memory);
    function getMaturityTime(bytes32 requestId) external view returns (uint256);
}

/// @notice GG Token (ERC-20 share) — 0xef417FCE1883c6653E7dC6AF7c6F85CCDE84Aa09
interface IGGToken {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
