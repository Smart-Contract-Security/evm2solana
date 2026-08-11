// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "contracts/allocation/IAllocationProvider.sol";

/**
 * @title AllocationProvider
 * @author Finceptor
 * @notice Contract implments allocation provider interface assuming that
 * {_calculateAllocation} function is implemented.
 * @dev Derived contracts must implement {_calculateAllocation} function.
 */
contract AllocationProvider is IAllocationProvider, Ownable, ReentrancyGuard {
    /// @notice Mapping of accounts to allocations
    mapping(address => uint256) private _allocations;
    /// @notice Total allocation reserved
    uint256 public totalAllocation;

    /**
     * @notice Set allocations of `accounts` to corresponding `amounts`
     * @dev This function can only be called by the owner.
     */
    function setBatchAllocation(
        address[] memory accounts,
        uint256[] memory allocations
    ) external onlyOwner {
        require(
            accounts.length == allocations.length,
            "AllocationProvider: accounts and allocations must be the same length"
        );
        for (uint256 i = 0; i < accounts.length; i++) {
            setAllocation(accounts[i], allocations[i]);
        }
    }

    /**
     * @notice Increase allocation of `_account` by `_amount`
     * @dev This function can only be called by the owner.
     */
    function increaseAllocation(address _account, uint256 _amount) external onlyOwner {
        require(_amount > 0, "AllocationProvider: amount is 0");
        uint allocation = allocationOf(_account) + _amount;
        setAllocation(_account, allocation);
    }

    /**
     * @notice Set allocation of `_account` to 0
     * @dev This function can only be called by the owner.
     */
    function revokeAllocation(address _account) external onlyOwner {
        setAllocation(_account, 0);
    }

    /**
     * @notice Set allocation of `_account` to `_amount`
     * @dev This function can only be called by the owner.
     */
    function setAllocation(address _account, uint256 _amount) public onlyOwner {
        require(_account != address(0), "AllocationProvider: beneficiary is the zero address");
        uint256 current = allocationOf(_account);
        _allocations[_account] = _amount;
        totalAllocation = totalAllocation - current + _amount;
    }

    /**
     * @notice Allocation of `_account`
     */
    function allocationOf(address _account) public view returns (uint256) {
        return _allocations[_account];
    }
}
