// SPDX-License-Identifier: BUSL-1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.35;

/// @custom:security-contact security@sivo.com
contract FiatStore {
    /// @custom:storage-location erc7201:sivo.storage.Fiat
    struct FiatStorage {
        uint8 decimals;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("sivo.storage.Fiat")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FiatStorageLocation =
        0x73cc089f90704b6bc518456f580e4c7bd5c5cb41064d9a6f723ef84284275b00;

    function _getFiatStorage() internal pure returns (FiatStorage storage $) {
        assembly {
            $.slot := FiatStorageLocation
        }
    }
}
