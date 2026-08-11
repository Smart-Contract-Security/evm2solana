// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LidoAdapterCommon} from "../../../shared/adapters/stake/LidoAdapterCommon.sol";

/// @title LidoAdapter (Ethereum)
contract LidoAdapter is LidoAdapterCommon {
    function protocolName() external pure override returns (string memory) {
        return "lido";
    }

    // ============ Ethereum Mainnet Addresses ============

    function _stETH() internal pure override returns (address) {
        return 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    }

    function _stMATIC() internal pure override returns (address) {
        return 0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599;
    }

    function _wstETH() internal pure override returns (address) {
        return 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    }

    function _strETHVault() internal pure override returns (address) {
        return 0x277C6A642564A91ff78b008022D65683cEE5CCC5;
    }

    function _csaAccount() internal pure override returns (address) {
        return 0x4d72BFF1BeaC69925F8Bd12526a39BAAb069e5Da;
    }

    function _ggAccountant() internal pure override returns (address) {
        return 0xc873F2b7b3BA0a7faA2B56e210E3B965f2b618f5;
    }
}
