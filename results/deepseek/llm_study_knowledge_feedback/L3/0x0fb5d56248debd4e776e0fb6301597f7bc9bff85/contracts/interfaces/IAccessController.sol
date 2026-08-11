// SPDX-License-Identifier: MIT

import 'solana';

interface IAccessController {
    enum PauseScope { Deposits, Withdrawals, Swaps, All }

    function GUARDIAN_ROLE() external view returns (bytes32);
    function PARAM_MANAGER_ROLE() external view returns (bytes32);
    function TREASURY_MANAGER_ROLE() external view returns (bytes32);
    function ROUTER_ROLE() external view returns (bytes32);
    function ADMIN_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function globalSwapsPaused() external view returns (bool);
    function assetPaused(address asset, PauseScope scope) external view returns (bool);
    function pairPaused(address a, address b) external view returns (bool);
}