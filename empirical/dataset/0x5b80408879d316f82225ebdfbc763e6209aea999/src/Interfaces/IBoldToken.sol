// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";

interface IBoldToken is IERC20MetadataUpgradeable, IERC20PermitUpgradeable {
    function setCollateralRegistry(address _collateralRegistryAddress) external;

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;

    function sendToPool(address _sender, address poolAddress, uint256 _amount) external;

    function returnFromPool(address poolAddress, address user, uint256 _amount) external;

    // CCIP Integration functions
    function getCCIPAdmin() external view returns (address);
    
    function initializeCCIP(address[] calldata _tokenPools) external;
    
    function removeCCIPTokenPool(address _tokenPool) external;
    
    function burn(uint256 _amount) external;
    
    function ccipTokenPools(address _tokenPool) external view returns (bool);
    
    function ccipTokenPoolsLocked() external view returns (bool);
}
