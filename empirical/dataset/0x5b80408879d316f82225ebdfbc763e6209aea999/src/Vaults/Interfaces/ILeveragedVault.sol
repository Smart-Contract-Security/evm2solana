// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

interface ILeveragedVault is IERC4626, IERC721Receiver {
    // ============================================
    // Events
    // ============================================
    
    event TroveReceived(uint256 indexed troveId, address indexed from);
    event Rebalanced(uint256 oldLeverage, uint256 newLeverage);
    event LeverUpExecuted(uint256 flashLoanAmount, uint256 boldAmount);
    event LeverDownExecuted(uint256 flashLoanAmount, uint256 minBoldAmount);
    event TargetLeverageUpdated(uint256 oldLeverage, uint256 newLeverage);
    event KeeperUpdated(address indexed keeper, bool authorized);
    event LeverageAdjusterUpdated(address indexed adjuster, bool authorized);
    event DepositFeeCollected(address indexed depositor, uint256 feeAmount);

    // ============================================
    // Errors
    // ============================================
    
    error TroveAlreadySet();
    error TroveNotSet();
    error InvalidTroveNFT();
    error ZeroAddress();
    error InvalidLeverage();
    error DepositTooSmall();
    error TroveUnderwater();
    error SlippageTooHigh(uint256 actualSlippageBps, uint256 maxSlippageBps);
    error UnauthorizedKeeper();
    error UnauthorizedLeverageAdjuster();
    error InvalidMinDeposit();

    // ============================================
    // View Functions
    // ============================================

    /// @notice Returns the trove ID that this vault manages
    function troveId() external view returns (uint256);

    /// @notice Returns the target leverage ratio in 18 decimals (e.g., 2e18 for 2x)
    function targetLeverageX18() external view returns (uint256);

    /// @notice Returns the current leverage ratio in 18 decimals
    function getCurrentLeverage() external view returns (uint256);

    /// @notice Returns the current collateral ratio in 18 decimals
    function getCurrentCollateralRatio() external view returns (uint256);
    
    /// @notice Returns whether an address is an authorized keeper
    function authorizedKeepers(address keeper) external view returns (bool);
    
    /// @notice Returns whether an address is an authorized leverage adjuster
    function authorizedLeverageAdjusters(address adjuster) external view returns (bool);
    
    /// @notice Returns the minimum deposit amount
    function minDeposit() external view returns (uint256);

    // ============================================
    // Slippage Estimation Functions
    // ============================================

    /// @notice Estimate slippage for a given deposit amount
    /// @param depositAmount The amount of collateral to deposit
    /// @return slippageBps The estimated slippage in basis points
    /// @return wouldRevert True if the deposit would revert due to slippage
    function estimateDepositSlippage(uint256 depositAmount) external returns (uint256 slippageBps, bool wouldRevert);
    
    /// @notice Estimate slippage for a given withdrawal amount
    /// @param withdrawAmount The amount of collateral to withdraw
    /// @return slippageBps The estimated slippage in basis points
    /// @return wouldRevert True if the withdrawal would revert due to slippage
    function estimateWithdrawSlippage(uint256 withdrawAmount) external returns (uint256 slippageBps, bool wouldRevert);

    // ============================================
    // Custom Slippage Functions
    // ============================================
    
    /// @notice Deposit collateral with custom slippage tolerance
    /// @param assets Amount of collateral to deposit
    /// @param receiver Address to receive vault shares
    /// @param maxSlippageBps Maximum slippage in basis points
    /// @return shares Amount of shares minted
    function depositWithSlippage(uint256 assets, address receiver, uint256 maxSlippageBps) external returns (uint256 shares);
    
    /// @notice Withdraw collateral with custom slippage tolerance
    /// @param assets Amount of collateral to withdraw
    /// @param receiver Address to receive collateral
    /// @param owner Address that owns the shares
    /// @param maxSlippageBps Maximum slippage in basis points
    /// @return shares Amount of shares burned
    function withdrawWithSlippage(uint256 assets, address receiver, address owner, uint256 maxSlippageBps) external returns (uint256 shares);
    
    /// @notice Redeem shares with custom slippage tolerance
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive collateral
    /// @param owner Address that owns the shares
    /// @param maxSlippageBps Maximum slippage in basis points
    /// @return assets Amount of collateral received
    function redeemWithSlippage(uint256 shares, address receiver, address owner, uint256 maxSlippageBps) external returns (uint256 assets);

    // ============================================
    // Keeper Functions
    // ============================================

    /// @notice Rebalances the trove to match the target leverage
    /// @param maxSlippageBps Maximum slippage tolerance in basis points
    /// @dev Only authorized keepers can call to rebalance
    function rebalance(uint256 maxSlippageBps) external;

    // ============================================
    // Admin Functions
    // ============================================
    
    /// @notice Update target leverage ratio
    /// @param newTargetLeverageX18 New target leverage in 18 decimals
    function setTargetLeverage(uint256 newTargetLeverageX18) external;
    
    /// @notice Set or revoke keeper authorization
    /// @param keeper Address to update
    /// @param authorized Whether the keeper is authorized
    function setKeeper(address keeper, bool authorized) external;
    
    /// @notice Set or revoke leverage adjuster authorization
    /// @param adjuster Address to update
    /// @param authorized Whether the adjuster is authorized
    function setLeverageAdjuster(address adjuster, bool authorized) external;

    /// @notice Pause deposits and withdrawals
    function pause() external;

    /// @notice Unpause deposits and withdrawals
    function unpause() external;
}

