// SPDX-License-Identifier: CC-BY-NC-ND-4.0

// ExponentialNoError and Exp are not available on Solana.
// Define them inline as simple structs since the original import fails.

struct Exp {
    uint64 mantissa;
}

library ExponentialNoError {
    function getExp(uint64 num) internal pure returns (Exp memory) {
        return Exp(num);
    }
}

/// @notice ITermManager represents a contract that manages all
interface ITermRepoCollateralManager {
    // ========================================================================
    // = State Variables  =====================================================
    // ========================================================================

    function termRepoLocker() external view returns (address);

    function maintenanceCollateralRatios(
        address
    ) external view returns (uint64);

    function initialCollateralRatios(address) external view returns (uint64);

    function numOfAcceptedCollateralTokens() external view returns (uint8);

    function collateralTokens(uint64 index) external view returns (address);

    function encumberedCollateralRemaining() external view returns (bool);

    function termController() external view returns (address);

    // ========================================================================
    // = Auction Functions  ===================================================
    // ========================================================================

    /// @param sender The sender's address
    /// @param collateralToken The address of the token to be used as collateral
    /// @param amount The amount of the token to lock
    function auctionLockCollateral(
        address sender,
        address collateralToken,
        uint64 amount
    ) external;

    /// @param sender The sender's address
    /// @param collateralToken The address of the token used as collateral
    /// @param amount The amount of collateral tokens to unlock
    function auctionUnlockCollateral(
        address sender,
        address collateralToken,
        uint64 amount
    ) external;

    /// @notice Marks a borrower's currently locked collateral as encumbered across all accepted collateral tokens
    /// @param borrower The address of the borrower whose locked collateral is being encumbered
    function encumberExistingCollateral(
        address borrower
    ) external;

    // ========================================================================
    // = Rollover Functions  ==================================================
    // ========================================================================

    /// @param borrower The borrower's address
    /// @param rolloverProportion The proportion of the collateral to be unlocked, equal to the proportion of the collateral repaid
    /// @param rolloverTermRepoLocker The address of the new TermRepoLocker contract to roll into
    /// @return An array representing a list of accepted collateral token addresses
    /// @return An array containing the amount of collateral tokens to pairoff and transfer to new TermRepoLocker to roll into
    function transferRolloverCollateral(
        address borrower,
        uint64 rolloverProportion,
        address rolloverTermRepoLocker
    ) external returns (address[] memory, uint64[] memory);

    /// @param borrower The address of the borrower
    /// @param collateralToken The address of a collateral token
    /// @param amount The amount of collateral tokens to lock
    function acceptRolloverCollateral(
        address borrower,
        address collateralToken,
        uint64 amount
    ) external;

    /// @param rolloverAuction The address of the rollover auction
    function approveRolloverAuction(address rolloverAuction) external;

    // ========================================================================
    // = APIs  ================================================================
    // ========================================================================

    /// @param collateralToken The address of the collateral token to lock
    /// @param amount The amount of collateral token to lock
    function externalLockCollateral(
        address collateralToken,
        uint64 amount
    ) external;

    /// @notice Lock collateral on behalf of a borrower (DIAMOND_ROLE)
    /// @param borrower The address of the borrower for whom collateral is being locked
    /// @param collateralToken The address of the collateral token to lock
    /// @param amount The amount of collateral token to lock
    function externalLockCollateral(
        address borrower,
        address collateralToken,
        uint64 amount
    ) external;

    /// @param collateralToken The address of the collateral token to unlock
    /// @param amount The amount of collateral token to unlock
    function externalUnlockCollateral(
        address collateralToken,
        uint64 amount
    ) external;

    /// @notice Unlock collateral on behalf of a borrower (DIAMOND_ROLE)
    /// @param borrower The address of the borrower for whom collateral is being unlocked
    /// @param collateralToken The address of the collateral token to unlock
    /// @param amount The amount of collateral token to unlock
    function externalUnlockCollateral(
        address borrower,
        address collateralToken,
        uint64 amount
    ) external;

    /// @param borrower The address of the borrower
    /// @return The market value of borrower's locked collateral denominated in USD
    function getCollateralMarketValue(
        address borrower
    ) external view returns (uint64);

    // ========================================================================
    // = Margin Maintenance Functions  ========================================
    // ========================================================================

    /// @param borrower The address of the borrower
    function unlockCollateralOnRepurchase(address borrower) external;

    /// @param borrower The address of the borrower
    /// @param collateralTokenAddresses Collateral token addresses
    /// @param collateralTokenAmounts Collateral token amounts
    function journalBidCollateralToCollateralManager(
        address borrower,
        address[] calldata collateralTokenAddresses,
        uint64[] calldata collateralTokenAmounts
    ) external;

    /// @param borrower The address of the borrower
    /// @param sender The address of the entity (borrower or settler) initiating the collateral lock
    /// @param collateralToken Collateral token addresse
    /// @param amount Collateral token amount
    function mintOpenExposureLockCollateral(
        address borrower,
        address sender,
        address collateralToken,
        uint64 amount
    ) external;

    /// @param collateralToken The collateral token address of tokens locked
    /// @param amountToLock The amount of collateral tokens to lock
    function calculateMintableExposure(
        address collateralToken,
        uint64 amountToLock
    ) external view returns (Exp memory);

    /// @param borrower The address of the borrower
    /// @param collateralToken The collateral token address to query
    /// @return uint64 The amount of collateralToken locked on behalf of borrower
    function getCollateralBalance(
        address borrower,
        address collateralToken
    ) external view returns (uint64);

    /// @param borrower The address of the borrower
    /// @return An array of collateral token addresses
    /// @return An array collateral token balances locked on behalf of borrower
    function getCollateralBalances(
        address borrower
    ) external view returns (address[] memory, uint64[] memory);

    /// @param borrower The address of the borrower
    /// @param closureAmounts An array specifying the amounts of Term Repo exposure the liquidator proposes to cover in liquidation; an amount is required to be specified for each collateral token
    function batchDefault(
        address borrower,
        uint64[] calldata closureAmounts
    ) external;

    /// @param borrower The address of the borrower
    /// @param closureAmounts An array specifying the amounts of Term Repo exposure the liquidator proposes to cover in liquidation; an amount is required to be specified for each collateral token
    function batchLiquidation(
        address borrower,
        uint64[] calldata closureAmounts
    ) external;

    /// @param borrower The address of the borrower
    /// @param closureRepoTokenAmounts An array specifying the amounts of Term Repo Tokens the liquidator proposes to cover borrower repo exposure in liquidation; an amount is required to be specified for each collateral token
    function batchLiquidationWithRepoToken(
        address borrower,
        uint64[] calldata closureRepoTokenAmounts
    ) external;
}