// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DaemonRenderRequest} from "./DaemonRenderer.sol";

interface IDaemonRenderer {
    function tokenURI(DaemonRenderRequest memory request) external view returns (string memory);
    function renderSvg(DaemonRenderRequest memory request) external view returns (string memory);
}
