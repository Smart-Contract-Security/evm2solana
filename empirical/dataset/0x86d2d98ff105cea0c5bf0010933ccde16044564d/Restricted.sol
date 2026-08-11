// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "./MsgSource.sol";

abstract contract Restricted is MsgSource {
    address private _governor;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "ERC20: to the zero address");
        _governor = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() { require(_msgSender() == _governor, "Ownable: caller is not the owner"); _; }
    function owner() public view virtual returns (address) { return _governor; }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_governor, address(0)); _governor = address(0);
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_governor, newOwner); _governor = newOwner;
    }
}
