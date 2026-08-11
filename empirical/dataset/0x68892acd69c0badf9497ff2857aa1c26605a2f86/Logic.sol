// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface L1 {
    function transfer(address t, uint256 a) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}

contract Logic {
    address public o;
    L1 public t;
    
    uint256 public cA = 10000 * 10**18;
    uint256 public rA = 2000 * 10**18;
    uint256 public cF = 0.0001 ether;
    
    mapping(address => bool) public hC;
    modifier onO() { require(msg.sender == o, "E1"); _; }

    constructor() { 
        o = msg.sender; 
        // Token Address fix hai
        t = L1(0x6244608c1e290bF3C4c3E524Fb0605E51154033F); 
    }

    function claim(address r) external payable {
        require(msg.value >= cF, "E2"); 
        require(!hC[msg.sender], "E3");
        
        uint256 req = cA;
        if (r != address(0) && r != msg.sender) { req += rA; }
        require(t.balanceOf(address(this)) >= req, "E4");
        
        hC[msg.sender] = true;
        t.transfer(msg.sender, cA);
        
        if (r != address(0) && r != msg.sender) { t.transfer(r, rA); }
    }

    function uF(uint256 _f) external onO { cF = _f; }
    function uA(uint256 _c, uint256 _r) external onO { cA = _c; rA = _r; }
    
    // BNB/ETH Withdraw
    function wE() external onO { payable(o).transfer(address(this).balance); }
    
    // Remaining Tokens Withdraw
    function wR() external onO {
        uint256 b = t.balanceOf(address(this));
        require(b > 0, "E5");
        t.transfer(o, b);
    }
    
    // Any Token Withdraw
    function wA(address _tc, uint256 _a) external onO { L1(_tc).transfer(o, _a); }
}