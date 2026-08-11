// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

/// @custom:security-contact security@sivo.com
contract ShareStore {
    /// @custom:storage-location erc7201:sivo.storage.Share
    struct ShareStorage {
        uint8 decimals;
        uint assetTotalDeployed;
        uint assetTotalIdle;
        uint40 lastAccrualTime;
        uint64 discountRateSlope;
        uint64 discountRateBase;
        uint64 minIdleFactor;
        uint64 maxIdleFactor;
        mapping(address => bool) isVault;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("sivo.storage.Share")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ShareStorageLocation =
        0x5511b49c1294e538d1be51ecdb0ad6f3811c99158095bd8880b406713705ba00;

    function _getShareStorage() internal pure returns (ShareStorage storage $) {
        assembly {
            $.slot := ShareStorageLocation
        }
    }
}
