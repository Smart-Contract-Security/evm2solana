// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IDefaultErrors} from "../IDefaultErrors.sol";

interface IUsrCompensationDistributor is IDefaultErrors {
    event Claimed(address indexed account, uint256 usrAmount, uint256 usdcAmount);
    event MerkleRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    event Withdrawn(address indexed token, address indexed receiver, uint256 amount);

    error InvalidProof();
    error ClaimExceedsAllocation(uint256 claimed, uint256 requested, uint256 totalAllocation);
    error MerkleRootNotSet();
    error UsrAmountTooSmall();

    function claim(
        uint256 _usrAmount,
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof
    ) external;

    function claimAll(
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof
    ) external;

    function claimWithPermit(
        uint256 _usrAmount,
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function claimAllWithPermit(
        uint256 _totalAllocation,
        bytes32[] calldata _merkleProof,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    // solhint-disable-next-line style-guide-casing
    function USR_ADDRESS() external view returns (address);

    // solhint-disable-next-line style-guide-casing
    function USDC_ADDRESS() external view returns (address);

    // solhint-disable-next-line style-guide-casing
    function DECIMAL_SCALE() external view returns (uint256);

    function claimed(address _account) external view returns (uint256);

    function merkleRoot() external view returns (bytes32);
}
