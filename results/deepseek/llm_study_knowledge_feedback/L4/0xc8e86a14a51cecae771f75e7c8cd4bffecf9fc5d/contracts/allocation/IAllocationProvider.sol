// SPDX-License-Identifier: BSD-3-Clause

interface IAllocationProvider {
    /**
     * @dev Returns allocation in USD of `_account`
     * @param _account Account to check
     * @return Allocation of `_account`
     */
    function allocationOf(address _account) external view returns (uint64);

    /**
     * @dev Returns total allocation in USD
     * @return Total allocation
     */
    function totalAllocation() external view returns (uint64);
}