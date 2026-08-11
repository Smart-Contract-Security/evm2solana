// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IDeFiAdapter
/// @notice Unified DeFi protocol adapter base interface
/// @dev All protocol adapters must implement this interface, supporting Lending, DEX, Staking, Yield, Perp and other protocol types
interface IDeFiAdapter {
    // ============ Protocol Type Enum ============
    /// @notice Protocol type
    enum ProtocolType {
        Lending, // Lending protocol (Aave, Compound, Venus)
        DEX, // Decentralized exchange (Uniswap, Curve)
        Staking, // Staking protocol (Lido, Rocket Pool)
        Restaking, // Restaking (EigenLayer)
        Yield, // Yield aggregator (Yearn, Convex)
        Perp, // Perpetual contract (GMX, dYdX)
        Other // Other types
    }

    /// @notice Pool type (unified for all protocols)
    enum PoolType {
        Lending, // Lending pool
        Staked, // Staking pool
        Yield, // Yield pool
        Deposit, // Deposit pool
        Rewards, // Reward pool
        LiquidityPool, // Liquidity pool (DEX LP)
        Farming, // Farming pool
        Locked, // Locked pool
        Vesting // Vesting pool
    }

    /// @notice Token type
    enum TokenType {
        // ============ Common Types ============
        Deposit, // Deposit/Supply
        Withdraw, // Withdrawable
        Pending, // Pending/Processing

        Supply, // Supply asset
        Collateral, // Collateral (assets that can be used as collateral), some protocols like aave Collateral is a special Supply
        Debt, // Debt/Borrow
        Staked, // Staked
        Restaked, // Restaked (EigenLayer: restaked ETH)
        LP, // Liquidity token (Uniswap V2: LP token)
        PositionNFT, // Position NFT (Uniswap V3: position NFT)
        Yield, // Yield token
        Reward, // Reward token (claimable rewards)
        Locked, // Locked (time-locked assets)
        Vesting, // Vesting (gradually released assets)
        Other // Other types
    }

    /// @notice Token balance information
    /// @dev Contains both receipt token and underlying asset information:
    ///   - sharesToken: Receipt token address (address(0) if no receipt)
    ///   - shares: Receipt share amount
    ///   - sharesDecimals: Receipt token decimals
    ///   - assetToken: Underlying asset address
    ///   - amount: Underlying asset amount
    ///   - assetDecimals: Underlying asset decimals
    struct Token {
        address assetToken; // Underlying token address
        uint256 amount; // Underlying token amount
        uint8 assetDecimals; // Underlying token decimals

        address sharesToken; // Receipt token address (if receipt exists, otherwise address(0))
        uint256 shares; // Receipt token amount
        uint8 sharesDecimals; // Receipt token decimals

        TokenType tokenType; // Underlying token type
        string symbol; // Underlying token symbol, e.g.: USDT
    }

    /// @notice Reward information
    struct Reward {
        address rewardToken; // Reward token address
        uint256 amount; // Reward amount
        uint256 claimable; // Claimable amount
        uint8 decimals; // Reward token decimals
        string symbol; // Reward token symbol, e.g.: USDT
    }

    /// @notice Cooldown/Unlock information (applicable to staking, locking pools)
    struct Cooldown {
        uint256 cooldownEndTime; // Cooldown end time (0 means no cooldown)
        uint256 unstakeWindowEnd; // Withdrawal window end time (0 means unlimited), N seconds after cooldownEndTime
        uint256 amount; // Amount in cooldown
        uint256 tokenIdx; // Index of the corresponding token in Position.tokens[]
    }

    /// @notice General position information
    struct Position {
        bytes32 positionId; // Position unique identifier
        address poolAddress; // Pool address
        ProtocolType protocolType; // Protocol type
        PoolType poolType; // Pool type
        Token[] tokens; // Related tokens
        Reward[] rewards; // Reward information
        uint256 healthFactor; // Health factor (lending protocol specific, 1e18 precision, 0 means not applicable)
        Cooldown[] coolDowns; // Cooldown information array (empty array when not applicable)
        bytes extraData; // Extra data (protocol specific)
    }

    /// @notice Pool/Market information
    struct Pool {
        bytes32 poolId; // Pool unique identifier
        address poolAddress; // Pool address
        ProtocolType protocolType; // Protocol type
        PoolType poolType; // Pool type
        Token[] tokens; // Related tokens
        bool enabled; // Whether enabled
        bytes extraData; // Extra data (protocol specific)
    }

    // ============ Basic Methods ============

    /// @notice Protocol name
    /// @return Protocol name (e.g.: "Aave V3", "Uniswap V3")
    function protocolName() external pure returns (string memory);

    /// @notice Protocol version
    /// @return Version number
    function protocolVersion() external pure returns (string memory);

    /// @notice Protocol type
    /// @return Protocol type enum
    function protocolType() external pure returns (ProtocolType);

    /// @notice Get all positions of user in this protocol
    /// @param user User address
    /// @return positions Position array
    function getPositions(address user) external view returns (Position[] memory);

    /// @notice Get all positions of user in this protocol for a specific pool type
    /// @param user User address
    /// @param poolType Pool type
    /// @return positions Position array
    function getPositions(address user, PoolType poolType) external view returns (Position[] memory positions);

    /// @notice Get user position in a specific pool
    /// @param user User address
    /// @param poolId Pool unique identifier
    /// @return position Position
    function getPosition(address user, bytes32 poolId) external view returns (Position[] memory);

    /// @notice Get all supported pools under this protocol (only returns enabled pools)
    /// @return  Pool array
    function getSupportedPools() external view returns (Pool[] memory);

    /// @notice Get all supported pools of a specific pool type under this protocol (only returns enabled pools)
    /// @param poolType Pool type
    /// @return pools Pool array
    function getSupportedPools(PoolType poolType) external view returns (Pool[] memory);

    /// @notice Get pool information for a specific poolId under this protocol (only returns enabled pools)
    /// @param poolId Pool unique identifier
    /// @return pool Pool information
    function getSupportedPool(bytes32 poolId) external view returns (Pool memory);

    /// @notice Generate pool unique identifier
    /// @param poolType Pool type
    /// @param poolAddress Pool address
    /// @return poolId Pool unique identifier
    function getPoolId(PoolType poolType, address poolAddress) external view returns (bytes32);

    /// @notice Generate position unique identifier
    /// @param poolType Pool type
    /// @param poolAddress Pool address
    /// @param user User address
    /// @return positionId Position unique identifier
    function getPositionId(PoolType poolType, address poolAddress, address user) external view returns (bytes32);

    /// @notice Get shares amount for a given asset amount
    /// @dev Not all pool types support this conversion. Returns 0 if not supported.
    /// @param poolId Pool unique identifier
    /// @param asset Asset amount
    /// @return  asset shares (0 if conversion not supported for this pool type)
    function getShares(bytes32 poolId, uint256 asset) external view returns (uint256);

    /// @notice Get asset amount for a given shares amount
    /// @dev Not all pool types support this conversion. Returns 0 if not supported.
    /// @param poolId Pool unique identifier
    /// @param shares Shares amount
    /// @return  asset amount (0 if conversion not supported for this pool type)
    function getAssets(bytes32 poolId, uint256 shares) external view returns (uint256);

    // ============ General Management Methods ============
    /// @notice Batch add pools
    /// @param poolAddresses Pool address array
    /// @param poolTypes Pool type array
    function addPools(address[] calldata poolAddresses, PoolType[] calldata poolTypes) external;

    /// @notice Batch remove pools
    /// @param poolIds Pool unique identifier array
    function removePools(bytes32[] calldata poolIds) external;

    /// @notice Batch enable/disable pools
    /// @param poolIds Pool unique identifier array
    /// @param enabled Enable array
    function togglePools(bytes32[] calldata poolIds, bool[] calldata enabled) external;
}
