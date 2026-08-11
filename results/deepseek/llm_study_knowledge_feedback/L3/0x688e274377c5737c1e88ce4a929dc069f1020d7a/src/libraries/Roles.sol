import 'solana';

library Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes32 internal constant SUPER_ADMIN_ROLE = hex"7613a25ecc738585a232ad50a301178f12b3ba8887d13e138b523c4269c47689";
    bytes32 internal constant PAUSE_ROLE = hex"139c2898040ef16910dc9f44dc697df79363da767d8bc92f2e310312b816e46d";
    bytes32 internal constant CURATOR = hex"0aec9b08bc8c2cb62a91f52d33e3d77da4b3f3a63fc8b542a93abe3902ba929c";
    bytes32 internal constant MONITOR = hex"390ae1081063aad083f9b4572bbfcc286af7814a39b668db2927a1186deec81b";
    bytes32 internal constant OPERATOR = hex"523a704056dcd17bcf83bed8b68c59416dac1119be77755efe3bde0a64e46e0c";
    bytes32 internal constant FEE_CONTROLLER = hex"8a639721758084b2ff869ed05cee658aab46e6bdc69bca1b006bae9f55613c59";
    bytes32 internal constant TOKEN_MINTER = hex"262c70cb68844873654dc54487b634cb00850c1e13c785cd0d96a2b89b829472";
    bytes32 internal constant NAV_CALLER = hex"47bc4cfe7b2bde7da37514f11daac8409232278f94544d2e3175143878762e9f";
    bytes32 internal constant ONDO_TARGET_MANAGER = hex"a1b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0";
}