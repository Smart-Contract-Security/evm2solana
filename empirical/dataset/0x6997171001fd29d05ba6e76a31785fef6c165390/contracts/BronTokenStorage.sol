// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {IBronToken} from "./interfaces/IBronToken.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

abstract contract BronTokenStorage is IBronToken {
    using Checkpoints for Checkpoints.Trace208;

    // ------------------------------
    // Constants
    // ------------------------------

    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 ether;

    // ------------------------------
    // State variables
    // ------------------------------

    mapping(address => uint256) public lockedTokens;

    address public multisig;
    address public bronDao;

    address public oftContract;

    mapping(address => uint256) public loyaltyLockedTokens;
    address public loyaltyProgramContract;

    mapping(address => Checkpoints.Trace208) internal votesCheckpoints;
    Checkpoints.Trace208 internal totalCheckpoints;

    mapping(address => bool) public votesSynced;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;

}
