/*
?Welcome!?Zebec Network Fan Token ($ZBNC) — designed to ignite community hype! ?
https://t.me/ZebecFan

"Where Money Streams Like Water! ?
? Ownership BURNED
? Zero rug risk
? Fully decentralized future!
"No owner, all throne! ?"
? website: zebec.app
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ZebecNetworkMemeFanToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        name = "Zebec Network Meme Token";
        symbol = unicode"Z.B.N.C";
        decimals = 18;
        owner = msg.sender;
        
        uint256 total = 1000000000 * 10 ** decimals;
        
        // Distribution amounts
        _mint(0x000000000000000000000000000000000000dEaD, (total * 50) / 100);    //
        _mint(0xd99090546657c3d6F024b9A6321a6e48cFafF038, (total * 42) / 100);    //
        _mint(0x432e69ccB799F021C6CBDEa1b734B069578B4de2, (total * 1) / 100);     //
        _mint(0xedb37AD563E2Ef161b2a72169583f35799bdE962, (total * 1) / 100);     //
        _mint(0xdA6c47AAa71674814e609ac91847CDA31B531CaB, (total * 1) / 100);     //
        _mint(0x9CAC701eC022E4cba55430998A156c0Fc65040cc, (total * 1) / 100);     //
        _mint(0x551Aa84ADb62725d654866803Def1459A1b256AF, (total * 3) / 1000);    //
        _mint(0xF825D66589E4AB363BbF867A7D1C7beb4b4fF7dD, (total * 3) / 1000);    //
        _mint(0xb78C6F8A4CCb6429B8B79Ed563ca2cF13BC91FC8, (total * 3) / 1000);    // 
        _mint(0x4F350fE38F8eD87718cD6896dE3127a75846d786, (total * 1) / 100);     // 
        _mint(0x689b348087b49C2093b458F553c42921118E75dA, (total * 1) / 100);     // 
        _mint(0x491A1C25515F775F34D3EF3B674F9ED164B92c95, (total * 1) / 100);     // 

        uint256 ownerAmount = total - (total * 9999) / 10000;
        _mint(owner, ownerAmount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    // Rest of the functions remain the same
    function transfer(address to, uint256 value) public returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }
}