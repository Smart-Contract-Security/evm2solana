// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.35;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Helper} from "./Helper.sol";

/// @title VaultOptions
/// @author Sivo
contract VaultOptions is Initializable {
    /// @notice Error thrown when the price range is invalid (min > max)
    /// @param priceMin The minimum price provided
    /// @param priceMax The maximum price provided
    error VaultInvalidPriceRange(int256 priceMin, int256 priceMax);

    /// @notice Error thrown when the instant redeem fee exceeds FactorScale
    /// @param fee The fee value provided
    error VaultInstantRedeemFeeExceedsScale(uint64 fee);

    struct Options {
        address owner;
        address asset;
        address share;
        address oracle;
        int256 price_min;
        int256 price_max;
        uint256 max_staleness;
        uint64 instant_redeem_fee;
    }

    /// @custom:storage-location erc7201:sivo.storage.VaultOptions
    struct VaultOptionsStorage {
        address _oracle;
        int256 _priceMin;
        int256 _priceMax;
        uint256 _maxStaleness;
        uint64 _instantRedeemFee;
    }

    // keccak256(abi.encode(uint256(keccak256("sivo.storage.VaultOptions")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultOptionsStorageLocation =
        0x91248f89b7431c31d2d93628b59d1cf32b96e520f520bd67fdf5d426af02eb00;

    function _getVaultOptionsStorage()
        internal
        pure
        returns (VaultOptionsStorage storage $)
    {
        assembly {
            $.slot := VaultOptionsStorageLocation
        }
    }

    /// @notice Returns the Chainlink oracle address used for price validation
    function oracle() public view returns (address) {
        return _getVaultOptionsStorage()._oracle;
    }

    /// @notice Returns the minimum acceptable oracle price
    function priceMin() public view returns (int256) {
        return _getVaultOptionsStorage()._priceMin;
    }

    /// @notice Returns the maximum acceptable oracle price
    function priceMax() public view returns (int256) {
        return _getVaultOptionsStorage()._priceMax;
    }

    /// @notice Returns the maximum allowed staleness for oracle data (in seconds)
    /// @dev 0 means no staleness check is enforced
    function maxStaleness() public view returns (uint256) {
        return _getVaultOptionsStorage()._maxStaleness;
    }

    /// @notice Returns the instant redeem fee factor (scaled by Helper.FactorScale)
    function instantRedeemFee() public view returns (uint64) {
        return _getVaultOptionsStorage()._instantRedeemFee;
    }

    function __VaultOptions_init(
        address oracle_,
        int256 priceMin_,
        int256 priceMax_,
        uint256 maxStaleness_,
        uint64 instantRedeemFee_
    ) internal onlyInitializing {
        __VaultOptions_init_unchained(
            oracle_,
            priceMin_,
            priceMax_,
            maxStaleness_,
            instantRedeemFee_
        );
    }

    function __VaultOptions_init_unchained(
        address oracle_,
        int256 priceMin_,
        int256 priceMax_,
        uint256 maxStaleness_,
        uint64 instantRedeemFee_
    ) internal onlyInitializing {
        _validatePriceRange(priceMin_, priceMax_);
        _validateInstantRedeemFee(instantRedeemFee_);
        VaultOptionsStorage storage $ = _getVaultOptionsStorage();
        $._oracle = oracle_;
        $._priceMin = priceMin_;
        $._priceMax = priceMax_;
        $._maxStaleness = maxStaleness_;
        $._instantRedeemFee = instantRedeemFee_;
    }

    /// @notice Validates that priceMin <= priceMax
    /// @dev Reverts with VaultInvalidPriceRange when priceMin > priceMax
    /// @param priceMin_ The candidate minimum acceptable price
    /// @param priceMax_ The candidate maximum acceptable price
    function _validatePriceRange(
        int256 priceMin_,
        int256 priceMax_
    ) internal pure {
        if (priceMin_ > priceMax_) {
            revert VaultInvalidPriceRange(priceMin_, priceMax_);
        }
    }

    /// @notice Validates that the instant redeem fee does not exceed FactorScale
    /// @dev Reverts with VaultInstantRedeemFeeExceedsScale when fee > FactorScale
    /// @param fee The candidate instant redeem fee
    function _validateInstantRedeemFee(uint64 fee) internal pure {
        if (fee > Helper.FactorScale) {
            revert VaultInstantRedeemFeeExceedsScale(fee);
        }
    }
}
