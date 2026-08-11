// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPayoutDistributor} from "../interfaces/compensation/IPayoutDistributor.sol";

contract PayoutDistributor is
    IPayoutDistributor,
    AccessControlDefaultAdminRules,
    Pausable
{
    using SafeERC20 for IERC20;

    address public immutable TOKEN;

    bytes32 public merkleRoot;

    mapping(address => bool) public claimed;

    constructor(
        address _token,
        bytes32 _merkleRoot,
        address _admin
    ) AccessControlDefaultAdminRules(1 days, _admin) {
        require(_token != address(0), ZeroAddress());

        TOKEN = _token;
        merkleRoot = _merkleRoot;

        emit MerkleRootUpdated(bytes32(0), _merkleRoot);
    }

    function claim(uint256 _amount, bytes32[] calldata _merkleProof) external whenNotPaused {
        require(merkleRoot != bytes32(0), MerkleRootNotSet());
        require(_amount > 0, InvalidAmount(_amount));
        require(!claimed[msg.sender], AlreadyClaimed());

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), InvalidProof());

        claimed[msg.sender] = true;

        IERC20(TOKEN).safeTransfer(msg.sender, _amount);

        emit Claimed(msg.sender, _amount);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(oldRoot, _merkleRoot);
    }

    function withdraw(address _token, address _receiver, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_receiver != address(0), ZeroAddress());
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit Withdrawn(_token, _receiver, _amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }
}
