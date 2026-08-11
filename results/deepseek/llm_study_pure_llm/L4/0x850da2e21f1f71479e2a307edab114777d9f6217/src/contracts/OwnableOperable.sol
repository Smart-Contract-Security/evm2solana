// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./Ownable.sol";

contract OwnableOperable is Ownable {
    address public operator;

    uint256[49] private _gap;

    event OperatorChanged(address newAdmin);

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

    modifier onlyOperatorOrOwner() {
        require(msg.sender == operator || msg.sender == _owner(), "ARM: Only operator or owner can call this function.");
        _;
    }
}