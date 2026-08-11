// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MiTokenAirdrop {

    // DATOS DEL TOKEN
    string public name = "MiToken";
    string public symbol = "MTK";
    uint8 public decimals = 18;

    // OWNER
    address public owner;

    // SUPPLY TOTAL = 100 MILLONES
    uint256 public totalSupply = 100_000_000 * 10**18;

    // BALANCES
    mapping(address => uint256) public balanceOf;

    // ALLOWANCES ERC20
    mapping(address => mapping(address => uint256)) public allowance;

    // EVENTOS ERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // SOLO OWNER
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo propietario");
        _;
    }

    // CONSTRUCTOR
    constructor() {
        owner = msg.sender;

        // Todo el supply para el creador
        balanceOf[msg.sender] = totalSupply;

        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // TRANSFERENCIA NORMAL
    function transfer(address to, uint256 amount) public returns (bool) {

        require(to != address(0), "Direccion invalida");
        require(balanceOf[msg.sender] >= amount, "Saldo insuficiente");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    // APROBAR GASTO
    function approve(address spender, uint256 amount) public returns (bool) {

        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    // TRANSFERENCIA DESDE OTRA CUENTA
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {

        require(to != address(0), "Direccion invalida");
        require(balanceOf[from] >= amount, "Saldo insuficiente");
        require(allowance[from][msg.sender] >= amount, "No autorizado");

        allowance[from][msg.sender] -= amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);

        return true;
    }

    // AIRDROP MULTIPLE
    function transferMultiple(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) public onlyOwner returns (bool) {

        require(recipients.length == amounts.length, "Arrays diferentes");
        require(recipients.length <= 100, "Maximo 100 wallets");

        uint256 total = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }

        require(balanceOf[msg.sender] >= total, "Saldo insuficiente");

        for (uint256 i = 0; i < recipients.length; i++) {

            address recipient = recipients[i];
            uint256 amount = amounts[i];

            require(recipient != address(0), "Wallet invalida");

            balanceOf[msg.sender] -= amount;
            balanceOf[recipient] += amount;

            emit Transfer(msg.sender, recipient, amount);
        }

        return true;
    }

    // VER MI BALANCE
    function getMyBalance() public view returns (uint256) {
        return balanceOf[msg.sender];
    }

    // RENUNCIAR AL CONTROL DEL CONTRATO
    function renounceOwnership() public onlyOwner {
        owner = address(0);
    }
}