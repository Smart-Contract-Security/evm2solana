// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IShare
/// @author Sivo
/// @notice This interface defines the functions and events of the Share contract, which manages the tokenization of receivables. As receivables become available the can be purchased with a stablecoin like USDC, USDT, EURC, etc. The contract is [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) compliant. The `asset()` function returns the asset contract address. The contract also handles redemption of receivable tokens (a.k.a. sTokens depending on the asset: sivoUSDC, sivoUSDT, sEURC, etc.). Pricing increases dynamically based on the amount of receivables that are sold.
/// | Chain Type | Name | ID | Market | Currency | Contract Address |
/// | ---------- | ---- | -- | ------ | ------ | ---------------- |
/// | Mainnet      | Base | 8453 | US | USD | [0x7e6C74cFFC9B179BFd6C69C79682920Bf7611eF3](https://basescan.org/contract/0x7e6C74cFFC9B179BFd6C69C79682920Bf7611eF3) |
/// | Testnet      | Base Sepolia | 84532 | US | USD | [0x47BA8e2832Fce402aa21BD64E72824F062e91AE3](https://sepolia.basescan.org/contract/0x47BA8e2832Fce402aa21BD64E72824F062e91AE3) |
interface IShare is IERC20 {
    /// @notice Emitted when the discount rate parameters are updated
    /// @param discountRateBase The new base discount rate (per second)
    /// @param discountRateSlope The new discount rate slope (per second)
    event DiscountChange(uint discountRateBase, uint discountRateSlope);

    /// @notice Emitted when the idle factor parameters are updated
    /// @param minIdleFactor The new minimum idle factor
    /// @param maxIdleFactor The new maximum idle factor
    event IdleFactorChange(uint minIdleFactor, uint maxIdleFactor);

    /// @notice Emitted when the vault status is updated
    /// @param vault The vault address
    /// @param isVault The new vault status
    event UpdateVault(address vault, bool isVault);

    /// @notice Emitted when discount accrual is processed
    /// @param timeElapsed The time elapsed since the last accrual (in seconds)
    /// @param assetTotalDeployedStart The total assets deployed at the start of the accrual period
    /// @param assetTotalDeployedEnd The total assets deployed at the end of the accrual period
    /// @param assetTotalIdle The total assets idle during the accrual period
    /// @param totalSupply The total supply of shares
    event Accrue(
        uint timeElapsed,
        uint assetTotalDeployedStart,
        uint assetTotalDeployedEnd,
        uint assetTotalIdle,
        uint totalSupply
    );

    /// @notice Emitted when assets are deployed to RWAs
    /// @param vault The address of the vault that deployed the assets
    /// @param assets The amount of assets transferred
    /// @param data Additional data associated with deployment
    event ShareDeployAsset(address indexed vault, uint assets, bytes data);

    /// @notice Emitted when assets are recalled from RWAs
    /// @param vault The address of the vault that recalled the assets
    /// @param assets The amount of assets transferred
    /// @param data Additional data associated with recall
    event ShareRecallAsset(address indexed vault, uint assets, bytes data);

    /// @notice Error thrown when the timestamp exceeds the maximum value that can be stored
    /// @param timestamp The timestamp that caused the error
    error TimestampTooLarge(uint timestamp);

    /// @notice Error thrown when the caller is not a vault
    error ShareUnauthorizedVault();

    /// @notice Error thrown when there are insufficient idle assets
    /// @param assets The amount of assets that caused the error
    /// @param max The maximum amount of assets that can be deployed
    error ShareInsufficientIdleAssets(uint assets, uint max);

    /// @notice Error thrown when there are insufficient deployed assets
    /// @param assets The amount of assets that caused the error
    /// @param max The maximum amount of assets that can be deployed
    error ShareInsufficientDeployedAssets(uint assets, uint max);

    /// @notice Error thrown when the accrual is out of date
    /// @param timeElapsed The time elapsed since the last accrual
    error AccrualOutOfDate(uint timeElapsed);

    /// @notice Error thrown when min idle factor exceeds max idle factor
    /// @param minIdleFactor The min idle factor provided
    /// @param maxIdleFactor The max idle factor provided
    error ShareInvalidIdleFactorRange(
        uint64 minIdleFactor,
        uint64 maxIdleFactor
    );

    /// @notice Error thrown when idle factor exceeds the scale (1e18)
    /// @param idleFactor The idle factor that exceeded the scale
    error ShareIdleFactorExceedsScale(uint64 idleFactor);

    /// @notice Error thrown when a zero address is supplied where a non-zero address is required
    error ShareZeroAddress();

    /// @notice The slope component of the discount rate (per second)
    /// @dev Adjusted by dividing annual rate by SECONDS_PER_YEAR
    function discountRateSlope() external view returns (uint64);

    /// @notice The base component of the discount rate (per second)
    /// @dev Adjusted by dividing annual rate by SECONDS_PER_YEAR
    function discountRateBase() external view returns (uint64);

    /// @notice The minimum idle factor, representing the minimum percent of total assets that must remain idle
    /// @dev Scaled by FactorScale (1e18)
    function minIdleFactor() external view returns (uint64);

    /// @notice The maximum idle factor, representing the maximum percent of total assets that should remain idle
    /// @dev Scaled by FactorScale (1e18)
    function maxIdleFactor() external view returns (uint64);

    /// @notice The timestamp of the last accrual calculation
    /// @dev Stored as uint40 to save gas, can represent timestamps until year 36812
    function lastAccrualTime() external view returns (uint40);

    /// @notice Returns the total assets deployed
    /// @dev Calculated by applying discount accrual since last update
    function assetTotalDeployed() external view returns (uint);

    /// @notice Returns the total assets idle
    /// @dev Includes idle assets across all vaults
    function assetTotalIdle() external view returns (uint);

    /// @notice Calculates the accrual rate of deployed assets based on utilization
    /// @dev The accrual rate is used to determine how share value increases over time
    /// @param utilization_ The current utilization factor (ratio of assets in share to deployed assets)
    /// @return The calculated accrual rate including base rate plus slope component
    function accrueRate(uint utilization_) external view returns (uint);

    /// @notice Simulates an accrual at the current block, given current on-chain conditions
    /// @dev Uses the time elapsed since last accrual and calculates accrual
    /// @return timeElapsed The time elapsed since last accrual in seconds
    /// @return assetTotalDeployedStart The total assets deployed at the start of the accrual period
    /// @return assetTotalDeployedEnd The total assets deployed at the end of the accrual period
    /// @return assetTotalIdle The total assets idle during the accrual period
    function previewAccrue() external view returns (uint, uint, uint, uint);

    /// @notice Performs an accrual at the current block, given current on-chain conditions
    /// @dev Can only be called by linked vaults or accounts with OPERATOR_ROLE. Should be called by vaults before converting between assets and shares.
    function accrue() external;

    /// @notice Mints shares to the specified address
    /// @dev Can only be called by linked vaults
    /// @param to The address to mint shares to
    /// @param shares The total shares to mint
    /// @param assets The total assets added to the vault
    function mint(address to, uint256 shares, uint256 assets) external;

    /// @notice Burns shares from the specified owner
    /// @dev Can only be called by linked vaults
    /// @param owner The owner of the shares to burn
    /// @param shares The total shares to burn
    /// @param assets The total assets removed from the vault
    function burn(address owner, uint256 shares, uint256 assets) external;

    /// @notice Spends the allowance of shares from the owner to the spender
    /// @dev Can only be called by linked vaults
    /// @param owner The owner of the shares
    /// @param spender The spender of the shares
    /// @param shares The total shares to spend
    function spendAllowance(
        address owner,
        address spender,
        uint256 shares
    ) external;

    /// @notice Deploys assets from vault to RWA
    /// @dev Can only be called by linked vaults
    /// @dev Transfers assets from contract to vault and increases the assetTotalInRwa
    /// @dev Emits a TransferToRwa event after the transfer is complete
    /// @param assets Assets to transfer, or max uint to transfer all available
    /// @param data Additional data associated with deployment
    /// @return The amount of assets transferred
    /// @custom:error ShareInsufficientIdleAssets Thrown if trying to transfer more than available
    function deploy(
        uint256 assets,
        bytes calldata data
    ) external returns (uint256);

    /// @notice Recalls assets from RWA
    /// @dev Can only be called by linked vaults
    /// @dev Transfers assets from rwa to vault and decreases the assetTotalInRwa
    /// @dev Emits a TransferFromRwa event after the transfer is complete
    /// @param assets Assets to transfer, or max uint to transfer all available
    /// @param data Additional data associated with recall
    /// @return The amount of assets transferred
    /// @custom:error ShareInsufficientDeployedAssets Thrown if trying to settle more than the total sold amount
    function recall(
        uint256 assets,
        bytes calldata data
    ) external returns (uint256);

    /// @notice Returns the total assets managed by the share (deployed + idle)
    /// @dev Includes accrued discount on deployed assets
    /// @return The total assets
    function totalAssets() external view returns (uint);

    /// @notice Returns the maximum amount of assets that can be deployed to RWA
    /// @dev Calculated based on the minimum idle factor
    /// @return Max assets that can be deployed
    function maxDeploy() external view returns (uint);

    /// @notice Returns the annualized accrue factor based on current utilization
    /// @dev Useful for estimating expected annual yield
    /// @return The annual accrue factor scaled by FactorScale (1e18)
    function annualAccrueFactor() external view returns (uint);
}
