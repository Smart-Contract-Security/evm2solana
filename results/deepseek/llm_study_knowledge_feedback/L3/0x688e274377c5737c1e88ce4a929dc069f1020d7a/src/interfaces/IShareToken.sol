// SPDX-License-Identifier: MIT

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IShareToken is IERC20, IERC165 {
    event VaultAdded(address asset, address vault);
    event VaultRemoved(address asset, address vault);

    function mint(address to, uint64 amount) external;
    function burn(address from, uint64 amount) external;
    function addVault(address asset, address vault_) external;
    function removeVault(address asset) external;
    function vault(address asset) external view returns (address);
    function asset(address vault_) external view returns (address);
    function isVault(address vault_) external view returns (bool);
}