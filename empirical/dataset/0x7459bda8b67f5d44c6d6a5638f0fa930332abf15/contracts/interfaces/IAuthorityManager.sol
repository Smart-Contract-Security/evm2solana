// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "../libs/P2PLibrary.sol";

interface IAuthorityManager {
    function owner() external view returns (address);

    function propertyDetails(
        uint256 propertyId
    ) external view returns (P2PLibrary.PropertyData memory);

    function receiverAddress() external view returns (address);
}
