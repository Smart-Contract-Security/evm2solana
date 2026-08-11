// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

import {IERC7575} from "./IERC7575.sol";
import {IERC7540Deposit, IERC7540Redeem, IERC7540Operator} from "./IERC7540.sol";

/// @title IVault
/// @author Sivo
/// @notice This interface defines the functions and events of the Vault contract, which manages the tokenization of receivables. As receivables become available the can be purchased with a stablecoin like USDC, USDT, EURC, etc. The contract is [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) compliant. The `asset()` function returns the asset contract address. The contract also handles redemption of receivable tokens (a.k.a. sTokens depending on the asset: sivoUSDC, sivoUSDT, sEURC, etc.). Pricing increases dynamically based on the amount of receivables that are sold.
/// | Chain Type | Name | ID | Market | Asset | Contract Address |
/// | ---------- | ---- | -- | ------ |------ | ---------------- |
/// | Mainnet      | Base | 8453 | US | [USDC](https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) | [0x7e6C74cFFC9B179BFd6C69C79682920Bf7611eF3](https://basescan.org/address/0x7e6C74cFFC9B179BFd6C69C79682920Bf7611eF3) |
/// | Testnet      | Base Sepolia | 84532 | US | [USDC](https://sepolia.basescan.org/token/0x036CbD53842c5426634e7929541eC2318f3dCF7e) | [0x47BA8e2832Fce402aa21BD64E72824F062e91AE3](https://sepolia.basescan.org/address/0x47BA8e2832Fce402aa21BD64E72824F062e91AE3) |
interface IVault is
    IERC7575,
    IERC7540Deposit,
    IERC7540Redeem,
    IERC7540Operator
{
    /// @notice Emitted when assets are deployed to RWAs
    /// @param to The address of the receiver of the assets
    /// @param assets The amount of assets transferred
    /// @param data Additional data associated with deployment
    event VaultDeployAsset(address indexed to, uint assets, bytes data);

    /// @notice Emitted when assets are recalled from RWAs
    /// @param from The address of the sender of the assets
    /// @param assets The amount of assets transferred
    /// @param data Additional data associated with recall
    event VaultRecallAsset(address indexed from, uint assets, bytes data);

    /// @notice Error thrown when the oracle price is outside the acceptable range
    /// @param price The current oracle price
    /// @param priceMin The minimum acceptable price
    /// @param priceMax The maximum acceptable price
    error VaultPriceOutOfRange(int256 price, int256 priceMin, int256 priceMax);

    /// @notice Error thrown when the oracle round is incomplete
    /// @param roundId The round ID returned by the oracle
    /// @param answeredInRound The round in which the answer was computed
    error VaultOracleIncompleteRound(uint80 roundId, uint80 answeredInRound);

    /// @notice Error thrown when the oracle data is stale
    /// @param updatedAt The timestamp of the last oracle update
    /// @param maxStaleness The maximum allowed staleness in seconds
    error VaultOracleStale(uint256 updatedAt, uint256 maxStaleness);

    /// @notice Error thrown when a zero address is supplied where a non-zero address is required
    error VaultZeroAddress();

    /// @notice Emitted when the instant redeem fee is updated
    /// @param fee The new instant redeem fee factor
    event VaultInstantRedeemFeeChange(uint64 fee);

    /// @notice Emitted when accumulated fees are claimed
    /// @param to The address that received the fees
    /// @param assets The amount of fee assets transferred
    event VaultClaimFees(address indexed to, uint assets);

    /// @notice Emitted when the oracle address and staleness are updated
    /// @param oracle The new oracle address
    /// @param maxStaleness The new maximum staleness in seconds
    event VaultOracleChange(address indexed oracle, uint256 maxStaleness);

    /// @notice Emitted when the acceptable price range is updated
    /// @param priceMin The new minimum acceptable price
    /// @param priceMax The new maximum acceptable price
    event VaultPriceRangeChange(int256 priceMin, int256 priceMax);

    /// @notice Returns the maximum amount of assets that can be deployed from this vault
    /// @dev Capped by both Share.maxDeploy() and the vault's actual asset balance
    /// @return The maximum deployable assets
    function maxDeploy() external view returns (uint);

    /// @notice Deploys assets from vault to RWA
    /// @dev Can only be called by OPERATOR_ROLE
    /// @param assets Assets to transfer, or max uint to transfer all available
    /// @param data Additional data associated with deployment
    /// @return The amount of assets transferred
    function deploy(uint assets, bytes calldata data) external returns (uint);

    /// @notice Recalls assets from RWA
    /// @dev Can only be called by OPERATOR_ROLE
    /// @param assets Assets to transfer, or max uint to transfer all available
    /// @param data Additional data associated with recall
    /// @return The amount of assets transferred
    function recall(uint assets, bytes calldata data) external returns (uint);

    /// @notice Transitions pending deposits to claimable state
    /// @dev Can only be called by OPERATOR_ROLE
    /// @param assets The amount of assets to make claimable
    /// @param controller The address controlling this deposit
    /// @return shares The amount of shares allocated
    function claimableDeposit(
        uint256 assets,
        address controller
    ) external returns (uint256 shares);

    /// @notice Transitions pending redemptions to claimable state
    /// @dev Can only be called by OPERATOR_ROLE
    /// @param shares The amount of shares to make claimable
    /// @param controller The address controlling this redemption
    /// @return assets The amount of assets allocated
    function claimableRedeem(
        uint256 shares,
        address controller
    ) external returns (uint256 assets);

    /// @notice Updates the instant redeem fee factor
    /// @dev Can only be called by MANAGER_ROLE
    /// @param fee The new fee factor (scaled by Helper.FactorScale)
    function setInstantRedeemFee(uint64 fee) external;

    /// @notice Transfers accumulated instant redeem fees to a specified address
    /// @dev Can only be called by OPERATOR_ROLE
    /// @param to The address to receive the fees
    /// @return The amount of fee assets transferred
    function claimFees(address to) external returns (uint);
}
