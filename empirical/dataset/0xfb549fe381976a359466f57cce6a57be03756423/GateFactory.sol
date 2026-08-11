// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./Token.sol";

contract GateFactory {
    address public owner;
    address public lastToken;
    uint256 public count;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Built(address indexed token, bytes32 indexed salt);

    constructor(address owner_) {
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function build(bytes32 salt, address router, address tokenOwner) external onlyOwner returns (address token) {
        token = address(new GateLedger{salt: salt}(router, tokenOwner, address(this)));
        lastToken = token;
        count += 1;
        emit Built(token, salt);
    }

    function predict(bytes32 salt, address router, address tokenOwner) external view returns (address) {
        bytes memory init = abi.encodePacked(type(GateLedger).creationCode, abi.encode(router, tokenOwner, address(this)));
        bytes32 h = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(init)));
        return address(uint160(uint256(h)));
    }

    function transferOwnership(address next) external onlyOwner {
        require(next != address(0), "zero");
        emit OwnershipTransferred(owner, next);
        owner = next;
    }
}
