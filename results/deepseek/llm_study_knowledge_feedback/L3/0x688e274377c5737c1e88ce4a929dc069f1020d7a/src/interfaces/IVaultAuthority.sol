import 'solana';

interface IVaultAuthority {
    event RoleGranted(bytes32 role, address account, address sender);
    event RoleRevoked(bytes32 role, address account, address sender);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantAdmin(address account) external;
    function revokeAdmin(address account) external;
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
}