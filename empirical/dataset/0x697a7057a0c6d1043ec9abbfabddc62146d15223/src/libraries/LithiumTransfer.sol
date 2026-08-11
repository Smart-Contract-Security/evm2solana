// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {
    Storage,
    AssetVariant,
    InvalidAssetAddress,
    InvalidERC721Amount,
    ERC6909TransferFailed,
    UnknownTokenVariant,
    EthTransferFailed,
    InsufficientLiquidity,
    NothingToClaim
} from "../interfaces/ILithium.sol";

library LithiumTransfer {
    using SafeERC20 for IERC20;

    /// @notice Processes balance changes for a participant in a channel.
    /// @dev Handles deposits (from wallet or pool) and withdrawals (to wallet or pool).
    ///      For deposits exceeding pool liquidity, pulls from user's wallet or requires ETH for Native.
    ///      Returns ETH delta only for Native deposits; caller must provide msg.value accordingly.
    ///      When pool liquidity is insufficient for a deposit (liq < diff), the entire amount is pulled
    ///      from the wallet / msg.value; the existing pool balance is left untouched.
    /// @param liquidityKey Precomputed keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId)).
    /// @param assetVariant The asset type (e.g., Native, ERC20).
    /// @param assetAddress The asset contract address (address(0) for Native).
    /// @param tokenNumberId Token ID for non-fungibles; 0 for fungibles.
    /// @param user The participant's address.
    /// @param userLiq The participant's liquidity mapping in the pool.
    /// @param newBalance The new balance after update.
    /// @param previousBalance The previous balance.
    /// @param isWithdraw True if funds should withdraw to user's wallet (false: to pool).
    /// @return ethDelta Amount of ETH required from caller for Native deposits (0 otherwise).
    function processBalanceChanges(
        bytes32 liquidityKey,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        address user,
        mapping(bytes32 => uint256) storage userLiq,
        uint256 newBalance,
        uint256 previousBalance,
        bool isWithdraw
    ) internal returns (uint256 ethDelta) {
        if (newBalance == previousBalance) return 0;

        bool isDeposit = newBalance > previousBalance;
        uint256 diff = isDeposit ? newBalance - previousBalance : previousBalance - newBalance;
        uint256 liq = userLiq[liquidityKey];

        if (isDeposit) {
            // Deposit: Try pool first
            if (liq >= diff) {
                userLiq[liquidityKey] = liq - diff;
            } else if (assetVariant == AssetVariant.Native && assetAddress == address(0)) {
                // Require ETH from tx value
                ethDelta = diff;
            } else {
                // Pull from user's wallet
                depositAssetFrom(user, assetVariant, assetAddress, tokenNumberId, diff);
            }
        } else {
            // Withdrawal
            if (isWithdraw) {
                withdrawAssetTo(user, assetVariant, assetAddress, tokenNumberId, diff);
            } else {
                // Add to pool
                userLiq[liquidityKey] = liq + diff;
            }
        }
    }

    /// @notice Deposits an asset from a user to this contract.
    /// @dev Reverts on address(0) for non-Native variants, unknown variant, or transfer failure.
    ///      Uses safe transfers to prevent failures.
    ///      Fee-on-transfer tokens are not supported: the protocol assumes the full `amount` is
    ///      received. Tokens that deduct fees during transfer cause accounting mismatches within
    ///      the affected channel only (isolated by design). Both parties must verify token behavior
    ///      before co-signing states that reference the token — this is an off-chain responsibility.
    /// @param from The address to transfer from.
    /// @param variant The asset type.
    /// @param asset The asset contract address.
    /// @param id The token ID (for NFTs/6909).
    /// @param amount The amount to transfer (1 for ERC721).
    function depositAssetFrom(address from, AssetVariant variant, address asset, uint256 id, uint256 amount) internal {
        if (variant != AssetVariant.Native && asset == address(0)) revert InvalidAssetAddress();
        if (variant == AssetVariant.ERC20) {
            IERC20(asset).safeTransferFrom(from, address(this), amount);
        } else if (variant == AssetVariant.ERC721) {
            if (amount != 1) revert InvalidERC721Amount();
            IERC721(asset).safeTransferFrom(from, address(this), id);
        } else if (variant == AssetVariant.ERC1155) {
            IERC1155(asset).safeTransferFrom(from, address(this), id, amount, "");
        } else if (variant == AssetVariant.ERC6909) {
            if (!IERC6909(asset).transferFrom(from, address(this), id, amount)) revert ERC6909TransferFailed();
        } else {
            revert UnknownTokenVariant();
        }
    }

    /// @notice Withdraws an asset from this contract to a recipient.
    /// @dev Uses safe/low-level transfers. Reverts on failure or invalid variant.
    ///      Transfer revert propagation is intentional: if the recipient (e.g., a contract) reverts
    ///      the transfer, the entire settlement/revocation call reverts. Silently ignoring such failures
    ///      would cause permanent fund loss (assets leave the contract but are not received). Users must
    ///      ensure their address can accept transfers for the asset types used in their channels (EOAs
    ///      or compatible smart wallets).
    /// @param to The address to transfer to.
    /// @param variant The asset type.
    /// @param asset The asset contract address.
    /// @param id The token ID (for NFTs/6909).
    /// @param amount The amount to transfer (1 for ERC721).
    function withdrawAssetTo(address to, AssetVariant variant, address asset, uint256 id, uint256 amount) internal {
        if (asset == address(0)) {
            if (variant != AssetVariant.Native) revert InvalidAssetAddress();
            (bool success,) = to.call{value: amount}("");
            if (!success) revert EthTransferFailed();
        } else if (variant == AssetVariant.ERC20) {
            IERC20(asset).safeTransfer(to, amount);
        } else if (variant == AssetVariant.ERC721) {
            if (amount != 1) revert InvalidERC721Amount();
            IERC721(asset).safeTransferFrom(address(this), to, id);
        } else if (variant == AssetVariant.ERC1155) {
            IERC1155(asset).safeTransferFrom(address(this), to, id, amount, "");
        } else if (variant == AssetVariant.ERC6909) {
            if (!IERC6909(asset).transferFrom(address(this), to, id, amount)) revert ERC6909TransferFailed();
        } else {
            revert UnknownTokenVariant();
        }
    }

    /// @notice Allows a user to claim escrowed assets assigned during settlement or revocation.
    /// @dev Pull-payment: zeroes the claimable balance before transferring (CEI pattern).
    ///      Uses the strict `withdrawAssetTo` — if the user still cannot receive, the tx reverts
    ///      and the escrowed balance remains intact for a future attempt.
    /// @param store The global storage struct.
    /// @param variant The asset type.
    /// @param asset The asset contract address.
    /// @param id The token ID (for NFTs/6909).
    function claimAsset(Storage storage store, AssetVariant variant, address asset, uint256 id) internal {
        bytes32 key = keccak256(abi.encodePacked(variant, asset, id));
        uint256 amount = store.claimable[msg.sender][key];
        if (amount == 0) revert NothingToClaim();
        store.claimable[msg.sender][key] = 0;
        withdrawAssetTo(msg.sender, variant, asset, id, amount);
    }

    /// @notice Deposits an asset into the liquidity pool.
    /// @dev For non-Native, pulls from caller's wallet if amount > 0. For Native, returns required ETH.
    ///      Returns 0 immediately for zero-amount deposits (no revert, no transfer).
    /// @param store The global storage struct.
    /// @param assetVariant The asset type.
    /// @param assetAddress The asset contract address.
    /// @param tokenNumberId The token ID.
    /// @param amount The amount to deposit.
    /// @return ethRequired The ETH required (for Native; 0 otherwise).
    function depositToPool(
        Storage storage store,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 amount
    ) internal returns (uint256 ethRequired) {
        if (amount == 0) return 0;
        bytes32 liquidityKey = keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId));
        store.liquidityPool[msg.sender][liquidityKey] += amount;
        if (assetVariant == AssetVariant.Native && assetAddress == address(0)) {
            ethRequired = amount;
        } else {
            depositAssetFrom(msg.sender, assetVariant, assetAddress, tokenNumberId, amount);
        }
    }

    /// @notice Withdraws an asset from the liquidity pool to caller's wallet.
    /// @dev Checks sufficient liquidity before transfer. Reverts on insufficiency.
    /// @param store The global storage struct.
    /// @param assetVariant The asset type.
    /// @param assetAddress The asset contract address.
    /// @param tokenNumberId The token ID.
    /// @param amount The amount to withdraw.
    function withdrawFromPool(
        Storage storage store,
        AssetVariant assetVariant,
        address assetAddress,
        uint256 tokenNumberId,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        bytes32 liquidityKey = keccak256(abi.encodePacked(assetVariant, assetAddress, tokenNumberId));
        mapping(bytes32 => uint256) storage liquidity = store.liquidityPool[msg.sender];
        uint256 liq = liquidity[liquidityKey];
        if (liq < amount) revert InsufficientLiquidity();
        unchecked {
            liquidity[liquidityKey] = liq - amount;
        }
        withdrawAssetTo(msg.sender, assetVariant, assetAddress, tokenNumberId, amount);
    }
}
