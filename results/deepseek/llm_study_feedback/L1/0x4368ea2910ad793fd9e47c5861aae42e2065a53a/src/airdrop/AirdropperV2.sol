// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AirdropperV2 {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        _owner = tx.accounts[0].key;
        emit OwnershipTransferred(address(0), tx.accounts[0].key);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function airdropTokens(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 length = recipients.length;
        IERC20 tokenContract = IERC20(token);
        unchecked {
            for (uint256 i = 0; i < length; i++) {
                tokenContract.transferFrom(
                    tx.accounts[0].key,
                    recipients[i],
                    amounts[i]
                );
            }
        }
    }
}