// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import 'solana';

contract AirdropperV2 {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function airdropTokens(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        uint256 length = recipients.length;
        address tokenContract = token;
        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory ret) = tokenContract.call{accounts: [msg.sender, tokenContract]}(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender,
                    recipients[i],
                    amounts[i]
                )
            );
            require(success, "Token transfer failed");
        }
    }
}