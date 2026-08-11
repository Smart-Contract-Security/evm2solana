// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract HelloVerify {
    string  public message;
    uint256 public number;
    address public immutable deployer;

    event MessageUpdated(string newMessage);

    constructor(string memory _message, uint256 _number) {
        message  = _message;
        number   = _number;
        deployer = msg.sender;
    }

    function setMessage(string calldata _message) external {
        require(msg.sender == deployer, "not deployer");
        message = _message;
        emit MessageUpdated(_message);
    }
}
