// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDeFiAdapter} from "../interfaces/IDeFiAdapter.sol";
import {ErrorsLib} from "./ErrorsLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Utils
/// @notice Token operation utility library
library Utils {
    /// @notice Get token decimals
    /// @param token Token address
    /// @return Token decimals, returns default value 18 if failed to get
    function getTokenDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) return 18;
        return IERC20Metadata(token).decimals();
    }

    function getTokenSymbol(address token) internal view returns (string memory) {
        if (token == address(0)) return "";

        (bool success, bytes memory data) =
            token.staticcall(
                abi.encodeWithSelector(0x95d89b41) // symbol()
            );

        if (!success) return "";

        if (data.length == 32) {
            bytes32 raw = abi.decode(data, (bytes32));
            // All zeros → empty string
            if (raw == bytes32(0)) {
                return "";
            }
            // Otherwise treat as bytes32 symbol (e.g., MKR)
            return bytes32ToString(raw);
        }

        if (data.length >= 64) {
            return abi.decode(data, (string));
        }

        return "";
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    /// @notice Resize Token array
    function resizeTokenArray(IDeFiAdapter.Token[] memory array, uint256 newLength) internal pure {
        require(newLength <= array.length, ErrorsLib.LENGTH_EXCEEDS_LIMIT);

        assembly {
            mstore(array, newLength)
        }
    }

    /// @notice Extract valid elements from temporary array to new array (using inline assembly optimization)
    /// @param array Temporary array (may contain unused elements)
    /// @param newLength Valid element count
    /// @return result Resized array
    function trimPositionArray(IDeFiAdapter.Position[] memory array, uint256 newLength) internal pure returns (IDeFiAdapter.Position[] memory) {
        require(newLength <= array.length, ErrorsLib.LENGTH_EXCEEDS_LIMIT);

        if (newLength == 0) {
            return new IDeFiAdapter.Position[](0);
        }
        if (newLength == array.length) {
            return array;
        }
        assembly {
            mstore(array, newLength)
        }
        return array;
    }

    function trimRewardArray(IDeFiAdapter.Reward[] memory array, uint256 newLength) internal pure returns (IDeFiAdapter.Reward[] memory) {
        require(newLength <= array.length, ErrorsLib.LENGTH_EXCEEDS_LIMIT);

        if (newLength == 0) {
            return new IDeFiAdapter.Reward[](0);
        }

        if (newLength == array.length) {
            return array;
        }
        assembly {
            mstore(array, newLength)
        }
        return array;
    }

    function trimPoolArray(IDeFiAdapter.Pool[] memory array, uint256 newLength) internal pure returns (IDeFiAdapter.Pool[] memory) {
        require(newLength <= array.length, ErrorsLib.LENGTH_EXCEEDS_LIMIT);

        if (newLength == 0) {
            return new IDeFiAdapter.Pool[](0);
        }

        if (newLength == array.length) {
            return array;
        }
        assembly {
            mstore(array, newLength)
        }
        return array;
    }
}

