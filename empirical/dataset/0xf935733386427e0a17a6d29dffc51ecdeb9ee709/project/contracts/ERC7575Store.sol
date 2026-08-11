// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {Memory} from "@openzeppelin/contracts/utils/Memory.sol";

/// @title ERC7575Store
/// @author Sivo
/// @custom:security-contact security@sivo.com
contract ERC7575Store is Initializable {
    error ERC7575ZeroAddress();
    error ERC7575AssetDecimalsExceedsShareDecimals(
        uint8 assetDecimals,
        uint8 shareDecimals
    );

    /// @custom:storage-location erc7201:sivo.storage.ERC7575
    struct ERC7575Storage {
        address _share;
        address _asset;
        uint8 _assetDecimals;
        uint _accumulatedFees;
    }

    // keccak256(abi.encode(uint256(keccak256("sivo.storage.ERC7575")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC7575StorageLocation =
        0xded009ad9b938d1a1baff1d97e239efee9c206ea56ae29f5a0cade6f16ce7500;

    function _getERC7575Storage()
        internal
        pure
        returns (ERC7575Storage storage $)
    {
        assembly {
            $.slot := ERC7575StorageLocation
        }
    }

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC-20 or ERC-777).
     */
    function __ERC7575_init(
        address asset_,
        address share_
    ) internal onlyInitializing {
        __ERC7575_init_unchained(asset_, share_);
    }

    function __ERC7575_init_unchained(
        address asset_,
        address share_
    ) internal onlyInitializing {
        if (asset_ == address(0) || share_ == address(0))
            revert ERC7575ZeroAddress();
        ERC7575Storage storage $ = _getERC7575Storage();
        $._asset = asset_;
        $._share = share_;
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(
            IERC20(asset_)
        );
        $._assetDecimals = success ? assetDecimals : 18;
        if ($._assetDecimals > IERC20(share_).decimals()) {
            revert ERC7575AssetDecimalsExceedsShareDecimals(
                $._assetDecimals,
                IERC20(share_).decimals()
            );
        }
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _tryGetAssetDecimals(
        IERC20 asset_
    ) private view returns (bool ok, uint8 assetDecimals) {
        Memory.Pointer ptr = Memory.getFreeMemoryPointer();
        (bool success, bytes32 decimals_, ) = LowLevelCall
            .staticcallReturn64Bytes(
                address(asset_),
                abi.encodeCall(IERC20.decimals, ())
            );
        Memory.unsafeSetFreeMemoryPointer(ptr);
        uint256 decimals = uint256(decimals_);
        return
            (success &&
                LowLevelCall.returnDataSize() >= 32 &&
                decimals <= type(uint8).max)
                ? (true, uint8(decimals))
                : (false, 0);
    }
}
