// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IUsrCompensationDistributor} from "../interfaces/compensation/IUsrCompensationDistributor.sol";

contract UsrCompensationDistributor is
    IUsrCompensationDistributor,
    AccessControlDefaultAdminRules,
    Pausable
{
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_SCALE = 1e12;

    address public immutable USR_ADDRESS;
    address public immutable USDC_ADDRESS;

    bytes32 public merkleRoot;

    mapping(address => uint256) public claimed;

    constructor(
        address _usr,
        address _usdc,
        bytes32 _merkleRoot,
        address _admin
    ) AccessControlDefaultAdminRules(1 days, _admin) {
        require(_usr != address(0), ZeroAddress());
        require(_usdc != address(0), ZeroAddress());

        USR_ADDRESS = _usr;
        USDC_ADDRESS = _usdc;
        merkleRoot = _merkleRoot;

        emit MerkleRootUpdated(bytes32(0), _merkleRoot);
    }

    function claim(
        uint256 _usrAmount,
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused {
        _claim(_usrAmount, _totalAllocation, _merkleProof);
    }

    function claimAll(
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused {
        uint256 alreadyClaimed = claimed[msg.sender];
        require(_totalAllocation > alreadyClaimed, ClaimExceedsAllocation(alreadyClaimed, 0, _totalAllocation));
        uint256 remaining = _totalAllocation - alreadyClaimed;
        _claim(remaining, _totalAllocation, _merkleProof);
    }

    function claimWithPermit(
        uint256 _usrAmount,
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused {
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try IERC20Permit(USR_ADDRESS).permit(msg.sender, address(this), _usrAmount, _deadline, _v, _r, _s) {} catch {}
        _claim(_usrAmount, _totalAllocation, _merkleProof);
    }

    function claimAllWithPermit(
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused {
        uint256 alreadyClaimed = claimed[msg.sender];
        require(_totalAllocation > alreadyClaimed, ClaimExceedsAllocation(alreadyClaimed, 0, _totalAllocation));
        uint256 remaining = _totalAllocation - alreadyClaimed;
        // solhint-disable-next-line no-empty-blocks
        try IERC20Permit(USR_ADDRESS).permit(msg.sender, address(this), remaining, _deadline, _v, _r, _s) {} catch {}
        _claim(remaining, _totalAllocation, _merkleProof);
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

    function _claim(
        uint256 _usrAmount,
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof
    ) internal {
        require(merkleRoot != bytes32(0), MerkleRootNotSet());
        require(_usrAmount >= DECIMAL_SCALE, UsrAmountTooSmall());

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _totalAllocation));
        require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), InvalidProof());

        uint256 alreadyClaimed = claimed[msg.sender];
        require(_totalAllocation >= alreadyClaimed, ClaimExceedsAllocation(alreadyClaimed, _usrAmount, _totalAllocation));
        require(
            _usrAmount <= _totalAllocation - alreadyClaimed,
            ClaimExceedsAllocation(alreadyClaimed, _usrAmount, _totalAllocation)
        );

        uint256 usdcAmount = _usrAmount / DECIMAL_SCALE;

        claimed[msg.sender] = alreadyClaimed + _usrAmount;

        IERC20(USR_ADDRESS).safeTransferFrom(msg.sender, address(this), _usrAmount);
        IERC20(USDC_ADDRESS).safeTransfer(msg.sender, usdcAmount);

        emit Claimed(msg.sender, _usrAmount, usdcAmount);
    }
}
