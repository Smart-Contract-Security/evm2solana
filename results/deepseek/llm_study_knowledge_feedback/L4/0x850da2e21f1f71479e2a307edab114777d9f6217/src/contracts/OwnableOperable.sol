import {AccountInfo} from "solana";

/**
 * @title Base contract that provides ownership and operational control
 * @author Origin Protocol Inc
 */
contract OwnableOperable {
    /// @notice The account that can request and claim withdrawals.
    address public operator;

    /// @notice The owner of the contract
    address public _owner;

    uint64[49] private _gap;

    event OperatorChanged(address newAdmin);

    function _initOwnableOperable(address _operator) internal {
        _setOperator(_operator);
    }

    /// @notice Set the account that can request and claim withdrawals.
    /// @param newOperator The address of the new operator.
    function setOperator(address newOperator) external {
        require(tx.accounts.dataAccount.key == _owner, "ARM: Only owner can call this function.");
        _setOperator(newOperator);
    }

    function _setOperator(address newOperator) internal {
        operator = newOperator;

        emit OperatorChanged(newOperator);
    }

    modifier onlyOperatorOrOwner() {
        require(tx.accounts.dataAccount.key == operator || tx.accounts.dataAccount.key == _owner, "ARM: Only operator or owner can call this function.");
        _;
    }
}