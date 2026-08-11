// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ILSDAdapter} from "../interfaces/ILSDAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BaseAdapter
/// @notice Common helpers for LSD adapters
abstract contract BaseAdapter is ILSDAdapter {
    // Custom errors replaced with string reverts for Solana compatibility
    // error InvalidAddress();
    // error NotConfigured();
    // error LengthMismatch();
    // error CallFailed();
    // error InvalidConfig(string reason);

    /// @dev Default decimals fallback when token does not implement decimals()
    uint8 internal constant DEFAULT_DECIMALS = 18;
    /// @dev Default symbol fallback when token does not implement symbol()
    string internal constant DEFAULT_SYMBOL = "UNKNOWN";

    function _requireNonZero(address addr) internal pure {
        if (addr == address(0)) revert("InvalidAddress");
    }

    function _staticCallUint256(address target, bytes memory data) internal view returns (uint256) {
        return _staticCallUint256(target, data, 0);
    }

    function _staticCallUint256(address target, bytes memory data, uint256 offset) internal view returns (uint256) {
        // Solang does not support staticcall; use call with empty value
        (bool success, bytes memory result) = target.call{value: 0}(data);
        if (!success) revert("CallFailed");
        if (result.length < offset + 32) revert("CallFailed");
        uint256 val;
        assembly {
            val := mload(add(add(result, 32), offset))
        }
        return val;
    }

    function _getNativeSymbol() internal view returns (string memory) {
        // block.chainid not available on Solana; use a fixed value or tx.chainid if available
        // For Solana, we default to "SOL" or use a hardcoded chain identifier.
        // Since Solana is the target, we return "SOL".
        return "SOL";
    }

    function _buildInfoWithUnderlyingToken(address lsdToken, address underlyingToken, uint256 rate)
        internal
        view
        returns (ExchangeRateInfo memory info)
    {
        return _buildInfo(lsdToken, underlyingToken, false, rate, "");
    }

    function _buildInfoNative(address lsdToken, uint256 rate, string memory nativeSymbol)
        internal
        view
        returns (ExchangeRateInfo memory info)
    {
        return _buildInfo(lsdToken, address(0), true, rate, nativeSymbol);
    }

    /// @notice Build ExchangeRateInfo with hardcoded lsdSymbol (for tokens with problematic symbol())
    function _buildInfoNativeWithSymbol(
        address lsdToken,
        string memory lsdSymbol,
        uint256 rate,
        string memory nativeSymbol
    ) internal view returns (ExchangeRateInfo memory info) {
        uint8 lsdDecimals = _safeDecimals(lsdToken);

        info = ExchangeRateInfo({
            lsdToken: lsdToken,
            lsdSymbol: lsdSymbol,
            lsdDecimals: lsdDecimals,
            underlyingAsset: address(0),
            underlyingSymbol: nativeSymbol,
            underlyingDecimals: 18,
            isNative: true,
            rate: rate,
            timestamp: block.timestamp
        });
    }

    /// @notice Build ExchangeRateInfo with hardcoded symbols (for tokens with problematic symbol())
    function _buildInfoWithSymbols(
        address lsdToken,
        string memory lsdSymbol,
        address underlyingToken,
        string memory underlyingSymbol,
        uint256 rate
    ) internal view returns (ExchangeRateInfo memory info) {
        uint8 lsdDecimals = _safeDecimals(lsdToken);
        uint8 underlyingDecimals = _safeDecimals(underlyingToken);

        info = ExchangeRateInfo({
            lsdToken: lsdToken,
            lsdSymbol: lsdSymbol,
            lsdDecimals: lsdDecimals,
            underlyingAsset: underlyingToken,
            underlyingSymbol: underlyingSymbol,
            underlyingDecimals: underlyingDecimals,
            isNative: false,
            rate: rate,
            timestamp: block.timestamp
        });
    }

    function _buildInfo(
        address lsdToken,
        address underlyingToken,
        bool isNative,
        uint256 rate,
        string memory nativeSymbol
    ) internal view returns (ExchangeRateInfo memory info) {
        uint8 lsdDecimals = _safeDecimals(lsdToken);
        string memory lsdSymbol = _safeSymbol(lsdToken);

        address underlyingAsset = isNative ? address(0) : underlyingToken;
        string memory underlyingSymbol;
        uint8 underlyingDecimals;

        if (isNative) {
            underlyingSymbol = nativeSymbol;
            underlyingDecimals = 18;
        } else {
            underlyingSymbol = _safeSymbol(underlyingToken);
            underlyingDecimals = _safeDecimals(underlyingToken);
        }

        info = ExchangeRateInfo({
            lsdToken: lsdToken,
            lsdSymbol: lsdSymbol,
            lsdDecimals: lsdDecimals,
            underlyingAsset: underlyingAsset,
            underlyingSymbol: underlyingSymbol,
            underlyingDecimals: underlyingDecimals,
            isNative: isNative,
            rate: rate,
            timestamp: block.timestamp
        });
    }

    /// @dev Safely fetch token symbol; falls back to "UNKNOWN" if call reverts.
    /// Solang does not support try-catch; we use low-level call and check success.
    function _safeSymbol(address token) internal view returns (string memory) {
        (bool success, bytes memory data) = token.call{value: 0}(abi.encodeWithSignature("symbol()"));
        if (success && data.length >= 32) {
            // Decode the returned string
            // Since it's a dynamic type, we need to decode properly
            // The returned data is ABI-encoded: offset (32 bytes) + length (32 bytes) + string data
            // We can use abi.decode if the data is correctly formatted.
            // But to be safe, we check length and decode.
            // However, if the call succeeded, we assume the return data is a valid string.
            // We'll use assembly to extract the string.
            // Alternatively, we can use abi.decode(data, (string)) but that might revert if malformed.
            // We'll do a manual extraction.
            uint256 offset;
            uint256 length;
            assembly {
                offset := mload(add(data, 32))
                length := mload(add(data, add(32, offset)))
            }
            if (offset == 32 && length <= (data.length - 64)) {
                bytes memory result = new bytes(length);
                for (uint256 i = 0; i < length; i++) {
                    result[i] = data[64 + i];
                }
                return string(result);
            }
        }
        return DEFAULT_SYMBOL;
    }

    /// @dev Safely fetch token decimals; falls back to 18 if call reverts.
    /// Solang does not support try-catch; we use low-level call and check success.
    function _safeDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory data) = token.call{value: 0}(abi.encodeWithSignature("decimals()"));
        if (success && data.length >= 32) {
            // decimals returns uint8, which is left-padded to 32 bytes
            uint8 d;
            assembly {
                d := byte(31, mload(add(data, 32)))
            }
            return d;
        }
        return DEFAULT_DECIMALS;
    }

    /// @dev Convert bytes32 to string, stripping trailing zero bytes
    function _bytes32ToString(bytes32 b) internal pure returns (string memory) {
        uint256 len = 0;
        while (len < 32 && b[len] != 0) {
            len++;
        }
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = b[i];
        }
        return string(result);
    }
}