// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

contract WalletBasedAuth {
    address public owner;
    mapping(address => bool) public registeredAddresses;
    address[] private registeredAddressesList;

    event LoginSuccess(address user);
    event LoginFailure(address user);
    event AddressAdded(address user);
    event AddressRemoved(address user);
    event AddressesAdded(address[] users);
    event AddressesRemoved(address[] users);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can perform this action.");
        _;
    }

    constructor() {
        owner = msg.sender;
        addUserManual(msg.sender);
    }

    fallback() external payable {
        revert("Contract does not accept Ether");
    }

    receive() external payable {
        revert("Contract does not accept Ether");
    }

    function addUserManual(address user) public onlyOwner {
        require(!registeredAddresses[user], "Address is already registered.");
        registeredAddresses[user] = true;
        registeredAddressesList.push(user);
        emit AddressAdded(user);
    }

    function addUsersManual(address[] memory users) public onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            if (!registeredAddresses[users[i]]) {
                registeredAddresses[users[i]] = true;
                registeredAddressesList.push(users[i]);
            }
        }
        emit AddressesAdded(users);
    }

    function removeUser(address user) public onlyOwner {
        require(registeredAddresses[user], "Address is not registered.");
        registeredAddresses[user] = false;
        emit AddressRemoved(user);
    }

    function removeUsers(address[] memory users) public onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            if (registeredAddresses[users[i]]) {
                registeredAddresses[users[i]] = false;
            }
        }
        emit AddressesRemoved(users);
    }

    function isRegistered(address user) public view returns (bool) {
        return registeredAddresses[user];
    }

    function login() public {
        if (registeredAddresses[msg.sender]) {
            emit LoginSuccess(msg.sender);
        } else {
            emit LoginFailure(msg.sender);
        }
    }

    function getAllRegisteredAddresses() public view onlyOwner returns (address[] memory) {
        return registeredAddressesList;
    }
}