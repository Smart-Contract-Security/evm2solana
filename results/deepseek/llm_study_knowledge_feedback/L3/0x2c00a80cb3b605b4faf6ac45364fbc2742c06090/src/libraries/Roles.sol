import 'solana';

library Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes32 internal constant SUPER_ADMIN_ROLE = sha256("global:SUPER_ADMIN_ROLE");
    bytes32 internal constant PAUSE_ROLE = sha256("global:PAUSE_ROLE");
    bytes32 internal constant CURATOR = sha256("global:CURATOR");
    bytes32 internal constant MONITOR = sha256("global:MONITOR");
    bytes32 internal constant OPERATOR = sha256("global:OPERATOR");
    bytes32 internal constant FEE_CONTROLLER = sha256("global:FEE_CONTROLLER");
    bytes32 internal constant TOKEN_MINTER = sha256("global:TOKEN_MINTER");
    bytes32 internal constant NAV_CALLER = sha256("global:NAV_CALLER");
    bytes32 internal constant ONDO_TARGET_MANAGER = sha256("global:ONDO_TARGET_MANAGER");
}