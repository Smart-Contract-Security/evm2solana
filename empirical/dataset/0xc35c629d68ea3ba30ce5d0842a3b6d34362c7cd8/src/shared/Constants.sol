// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @dev Role allows user to create and update pools along with pool administration
 */
bytes32 constant POOL_OPERATOR_ROLE = keccak256("POOL_OPERATOR");

/**
 * @dev Default RBAC admin role
 */
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
