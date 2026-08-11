// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

library Library {
    function bytesToString(bytes memory data) internal pure returns (string memory) {
        if (data.length != 32 || data[0] == 0) {
            return abi.decode(data, (string));
        }

        uint256 len = 0;

        // 计算实际字符串长度（遇到 0x00 停止）
        while (len < 32 && data[len] != 0) {
            len++;
        }

        bytes memory bytesArray = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            bytesArray[i] = data[i];
        }

        return string(bytesArray);
    }

    function getTokenInfo(address token) internal view returns (uint8 decimals, string memory name, string memory symbol) {
        if (token != address(0)) {
            ERC20 tokenContract = ERC20(token);
            decimals = tokenContract.decimals();

            bool success;
            bytes memory data;
            (success, data) = token.staticcall(abi.encodeWithSignature("name()"));
            if (success) {
                name = bytesToString(data);
            } else {
                name = "";
            }
            (success, data) = token.staticcall(abi.encodeWithSignature("symbol()"));
            if (success) {
                symbol = bytesToString(data);
            } else {
                symbol = "";
            }
        } else {
            decimals = 18;
            name = "ETH";
            symbol = "ETH";
        }
    }

    function isAToken(address token) internal view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("UNDERLYING_ASSET_ADDRESS()"));
        if (success && data.length == 32) {
            address underlying = abi.decode(data, (address));
            return underlying != address(0);
        }
        return false;
    }
}