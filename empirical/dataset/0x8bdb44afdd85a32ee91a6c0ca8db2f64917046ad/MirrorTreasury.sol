// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface MirrorTreasuryCoin {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface MirrorVaultNote {
    function store(uint256 amount) external;
}

contract MirrorTreasury {
    address public owner;
    address public token;
    address public vault;
    uint256 public routed;

    function bind(address owner_, address token_, address vault_) external {
        require(token == address(0), "bound");
        owner = owner_;
        token = token_;
        vault = vault_;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function note(uint256 amount) external {
        require(msg.sender == token, "token");
        routed += amount;
    }

    function pushVault(uint256 amount) external onlyOwner {
        require(MirrorTreasuryCoin(token).transfer(vault, amount), "send");
        MirrorVaultNote(vault).store(amount);
    }
}
