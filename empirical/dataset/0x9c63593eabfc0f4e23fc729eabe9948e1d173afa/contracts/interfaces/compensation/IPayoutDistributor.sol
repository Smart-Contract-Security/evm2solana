// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IDefaultErrors} from "../IDefaultErrors.sol";

interface IPayoutDistributor is IDefaultErrors {
    event Claimed(address indexed account, uint256 amount);
    event MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);

    error InvalidProof();
    error AlreadyClaimed();
    error MerkleRootNotSet();

    function claim(uint256 _amount, bytes32[] calldata _merkleProof) external;

    // solhint-disable-next-line style-guide-casing
    function TOKEN() external view returns (address);

    function claimed(address _account) external view returns (bool);

    function merkleRoot() external view returns (bytes32);
}
