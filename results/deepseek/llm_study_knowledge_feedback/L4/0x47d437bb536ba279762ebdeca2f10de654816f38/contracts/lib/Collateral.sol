//SPDX-License-Identifier: CC-BY-NC-ND-4.0

/// @dev Collateral info for price oracle
struct Collateral {
    address tokenAddress;
    uint64 initialCollateralRatio;
    uint64 maintenanceRatio;
    uint64 liquidatedDamage;
}