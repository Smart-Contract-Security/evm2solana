// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Roles
library Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    // 0x7613a25ecc738585a232ad50a301178f12b3ba8887d13e138b523c4269c47689
    bytes32 internal constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    // 0x139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    // 0x0aec9b08bc8c2cb62a91f52d33e3d77da4b3f3a63fc8b542a93abe3902ba929c
    bytes32 internal constant CURATOR = keccak256("CURATOR");
    // 0x390ae1081063aad083f9b4572bbfcc286af7814a39b668db2927a1186deec81b
    bytes32 internal constant MONITOR = keccak256("MONITOR");
    // 0x523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c
    bytes32 internal constant OPERATOR = keccak256("OPERATOR");
    // 0x8a639721758084b2ff869ed05cee658aab46e6bdc69bca1b006bae9f55613c59
    bytes32 internal constant FEE_CONTROLLER = keccak256("FEE_CONTROLLER");
    // 0x262c70cb68844873654dc54487b634cb00850c1e13c785cd0d96a2b89b829472
    bytes32 internal constant TOKEN_MINTER = keccak256("TOKEN_MINTER");
    // 0x47bc4cfe7b2bde7da37514f11daac8409232278f94544d2e3175143878762e9f
    bytes32 internal constant NAV_CALLER = keccak256("NAV_CALLER");
    //
    bytes32 internal constant ONDO_TARGET_MANAGER = keccak256("ONDO_TARGET_MANAGER");
}
