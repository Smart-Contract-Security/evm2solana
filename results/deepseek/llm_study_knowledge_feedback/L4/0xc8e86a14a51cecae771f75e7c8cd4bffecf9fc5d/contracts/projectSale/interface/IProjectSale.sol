// SPDX-License-Identifier: BSD-3-Clause

interface IProjectSale {
    /**
     * @dev Emitted when `_account` registers to sale
     */
    event Registered(address _account);

    /**
     * @dev Emitted when `_account` deposits `_amount` USD pegged coin
     */
    event Deposit(address _account, uint64 _amount);

    /**
     * @dev Register to sale
     *
     * Emits a {Registered} event.
     */
    function register(uint64 _timestamp, bytes calldata _signature) external;

    /**
     * @dev Returns true if `_account` is registered
     * @param _account Account to check
     */
    function isRegistered(address _account) external view returns (bool);

    /**
     * @dev Returns amount of pegged tokens to be transferred to deposit `_amount` pegged token
     * @param _amount Amount of USD to deposit.
     * @return Amount of pegged tokens to be transferred to deposit `_amount` pegged token
     */
    function depositAmountWithFees(uint64 _amount) external view returns (uint64);

    /**
     * @dev Deposit USD
     * @param _amount Amount of USD to deposit.
     *
     * Emits a {Deposit} event.
     */
    function deposit(uint64 _amount, uint64 _timestamp, bytes calldata _signature) external;

    /**
     * @dev Returns USD deposited by `_account`
     * @param _account Account to check
     */
    function depositedOf(address _account) external view returns (uint64);

    /**
     * @dev Returns depositable USD of `_account`
     * @param _account Account to check
     * @return Depositable USD of `_account`
     */
    function depositableOf(address _account) external view returns (uint64);

    /**
     * @dev Returns current sale value in terms of pegged token
     * @return uint64 current sale value
     */
    function totalSaleValue() external view returns (uint64);

    /**
     * @dev Returns total sale value cap in terms of pegged token
     * @return uint64 total sale value
     */
    function totalSaleValueCap() external view returns (uint64);

    /**
     * @notice Function to view the total public sale deposited of a user
     * @param _account is the address to check.
     * @return uint64 is the total public sale deposited.
     */
    function publicSaleDepositedOf(address _account) external view returns (uint64);

    /**
     * @dev Returns staking round allocation of user, excluding credit token allocation
     * @return uint64 staking round allocation of user
     */
    function stakingRoundAllocationOf(address _account) external view returns (uint64);

    function publicRoundAllocationOf(address _account) external view returns (uint64);

    function getSaleNom() external view returns (uint64);
}