// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CoreAccess } from "../base/CoreAccess.sol";
import { IBlocklist } from "../interfaces/IBlocklist.sol";
import { Roles } from "../libraries/Roles.sol";

/// @title Blocklist
contract Blocklist is CoreAccess, IBlocklist {
    mapping(address => bool) private _blocked;

    event BlocklistSet(address indexed account, bool blocked);
    event BlocklistReasonSet(address indexed account, bool blocked, string reason);

    constructor(address admin) CoreAccess(admin) { }

    function initialize(address admin) external {
        _initializeCoreAccess(admin);
    }

    function setBlocked(address account, bool blocked) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
        _blocked[account] = blocked;
        emit BlocklistSet(account, blocked);
    }

    function setBlockedWithReason(address account, bool blocked, string calldata reason)
        external
        onlyRole(Roles.DEFAULT_ADMIN_ROLE)
    {
        _blocked[account] = blocked;
        emit BlocklistSet(account, blocked);
        emit BlocklistReasonSet(account, blocked, reason);
    }

    function setBlockedBatch(address[] calldata accounts, bool[] calldata blocked)
        external
        onlyRole(Roles.DEFAULT_ADMIN_ROLE)
    {
        require(accounts.length == blocked.length, "Blocklist: length mismatch");
        for (uint256 i; i < accounts.length; ++i) {
            _blocked[accounts[i]] = blocked[i];
            emit BlocklistSet(accounts[i], blocked[i]);
        }
    }

    function isBlocked(address account) external view returns (bool) {
        return _blocked[account];
    }
}
