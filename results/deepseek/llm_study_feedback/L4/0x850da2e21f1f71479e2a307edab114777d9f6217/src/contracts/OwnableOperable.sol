// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract OwnableOperable {
    address public owner;
    address public operator;

    uint256[49] private _gap;

    event OperatorChanged(address newAdmin);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.accounts[0].key == owner, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyOperatorOrOwner() {
        require(tx.accounts[0].key == operator || tx.accounts[0].key == owner, "ARM: Only operator or owner can call this function.");
        _;
    }

    function _initOwnableOperable(address _operator) internal {
        _setOperator(_operator);
    }

    function setOperator(address newOperator) external onlyOwner {
        _setOperator(newOperator);
    }

    function _setOperator(address newOperator) internal {
        operator = newOperator;
        emit OperatorChanged(newOperator);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}