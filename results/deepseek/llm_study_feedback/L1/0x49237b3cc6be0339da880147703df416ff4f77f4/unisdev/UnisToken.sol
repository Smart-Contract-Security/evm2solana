// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'solana';

contract UnisToken {
    string public constant name     = "UNIS";
    string public constant symbol   = "UNIS";
    uint8  public constant decimals = 18;

    uint256 public constant SUPPLY = 100_000_000 * 1e18;
    uint256 public totalSupply = SUPPLY;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public admin;
    address public treasury;
    bool    public live;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    event Incinerated(address indexed from, uint256 amount);
    event Ignited(uint64 atTimestamp);
    event TreasurySet(address indexed prev, address indexed next);
    event AdminPassed(address indexed prev, address indexed next);
    event EthSwept(address indexed to, uint256 amount);

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert("NotAdmin");
        }
        _;
    }

    constructor() {
        admin = msg.sender;
        balanceOf[msg.sender] = SUPPLY;
        emit Transfer(address(0), msg.sender, SUPPLY);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _move(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) {
            if (a < value) {
                revert("InsufficientAllowance");
            }
            unchecked { allowance[from][msg.sender] = a - value; }
        }
        _move(from, to, value);
        return true;
    }

    function _move(address from, address to, uint256 value) internal {
        if (to == address(0)) {
            revert("ZeroAddress");
        }
        if (balanceOf[from] < value) {
            revert("InsufficientBalance");
        }
        if (!live && from != admin && to != admin) {
            revert("NotLive");
        }
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to]   += value;
        }
        emit Transfer(from, to, value);
    }

    function incinerate(uint256 value) external {
        if (balanceOf[msg.sender] < value) {
            revert("InsufficientBalance");
        }
        unchecked {
            balanceOf[msg.sender] -= value;
            totalSupply -= value;
        }
        emit Transfer(msg.sender, address(0), value);
        emit Incinerated(msg.sender, value);
    }

    function setTreasury(address t) external onlyAdmin {
        if (t == address(0)) {
            revert("ZeroAddress");
        }
        emit TreasurySet(treasury, t);
        treasury = t;
    }

    function ignite() external onlyAdmin {
        if (live) {
            revert("AlreadyLive");
        }
        live = true;
        emit Ignited(uint64(block.timestamp));
    }

    function sweepEth(address payable to, uint256 amount) external onlyAdmin {
        if (to == address(0)) {
            revert("ZeroAddress");
        }
        revert("eth sweep not supported on Solana");
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) {
            revert("ZeroAddress");
        }
        emit AdminPassed(admin, next);
        admin = next;
    }

    function cedeAdmin() external onlyAdmin {
        emit AdminPassed(admin, address(0));
        admin = address(0);
    }
}