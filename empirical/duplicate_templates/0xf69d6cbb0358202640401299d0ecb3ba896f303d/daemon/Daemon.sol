// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IGateCtl {
    function kindle() external;
}

interface IDaemonGate {
    function pulse(bytes32 poolId) external view returns (bytes32);
    function primaryPool() external view returns (bytes32);
    function seenByPool(bytes32 poolId) external view returns (uint64);
}

interface IDaemonArt {
    function glyphURI(address holder, uint256 slot, bytes32 pulse, uint64 spawnBlock) external view returns (string memory);
}

contract DaemonToken {
    string public constant name     = "DAEMONS";
    string public constant symbol   = "DAEMON";
    uint8  public constant decimals = 18;

    uint256 public constant SUPPLY = 6_666 * 1e18;
    uint256 public totalSupply = SUPPLY;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public bypass;
    mapping(address => uint64) public seenAt;

    address public admin;
    address public gate;
    address public art;
    address public husk;

    bool   public ignited;
    uint64 public igniteBlock;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    event Incinerated(address indexed from, uint256 amount);
    event Ignited(uint256 atBlock, uint64 atTimestamp);
    event BypassSet(address indexed account, bool flag);
    event GateBound(address indexed prev, address indexed next);
    event ArtBound(address indexed prev, address indexed next);
    event HuskBound(address indexed prev, address indexed next);
    event AdminPassed(address indexed prev, address indexed next);

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();
    error NotAdmin();
    error NotIgnited();
    error AlreadyIgnited();

    modifier onlyAdmin() { if (msg.sender != admin) revert NotAdmin(); _; }

    constructor() {
        admin = msg.sender;
        balanceOf[msg.sender] = SUPPLY;
        bypass[msg.sender] = true;
        bypass[DEAD]       = true;
        seenAt[msg.sender] = uint64(block.number);
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
            if (a < value) revert InsufficientAllowance();
            unchecked { allowance[from][msg.sender] = a - value; }
        }
        _move(from, to, value);
        return true;
    }

    function _move(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        if (balanceOf[from] < value) revert InsufficientBalance();
        if (!ignited && !bypass[from] && !bypass[to]) revert NotIgnited();
        if (balanceOf[to] == 0 && seenAt[to] == 0 && to != DEAD) {
            seenAt[to] = uint64(block.number);
        }
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to]   += value;
        }
        emit Transfer(from, to, value);
    }

    function incinerate(uint256 value) external {
        if (balanceOf[msg.sender] < value) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] -= value;
            totalSupply -= value;
        }
        emit Transfer(msg.sender, address(0), value);
        emit Incinerated(msg.sender, value);
    }

    function wholeCount(address holder) external view returns (uint256) {
        return balanceOf[holder] / 1e18;
    }

    function seedAt(address holder, uint256 slot) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, slot, "DAEMON"));
    }

    function glyphURI(address holder, uint256 slot) external view returns (string memory) {
        if (art == address(0)) return "";
        bytes32 corr;
        uint64  spawn;
        if (gate != address(0)) {
            bytes32 poolId = IDaemonGate(gate).primaryPool();
            corr  = IDaemonGate(gate).pulse(poolId);
            spawn = IDaemonGate(gate).seenByPool(poolId);
        }
        return IDaemonArt(art).glyphURI(holder, slot, corr, spawn);
    }

    function bindGate(address g) external onlyAdmin {
        emit GateBound(gate, g);
        gate = g;
        if (g != address(0)) {
            bypass[g] = true;
            emit BypassSet(g, true);
        }
    }

    function bindArt(address a) external onlyAdmin {
        emit ArtBound(art, a);
        art = a;
    }

    function bindHusk(address h) external onlyAdmin {
        emit HuskBound(husk, h);
        husk = h;
        if (h != address(0)) {
            bypass[h] = true;
            emit BypassSet(h, true);
        }
    }

    function setBypass(address account, bool flag) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        bypass[account] = flag;
        emit BypassSet(account, flag);
    }

    function setBypassMany(address[] calldata accounts, bool flag) external onlyAdmin {
        for (uint256 i; i < accounts.length; ) {
            address a = accounts[i];
            if (a != address(0)) {
                bypass[a] = flag;
                emit BypassSet(a, flag);
            }
            unchecked { i++; }
        }
    }

    function ignite() external onlyAdmin {
        if (ignited) revert AlreadyIgnited();
        ignited     = true;
        igniteBlock = uint64(block.number);
        if (gate != address(0)) {
            try IGateCtl(gate).kindle() {} catch {}
        }
        emit Ignited(block.number, uint64(block.timestamp));
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) revert ZeroAddress();
        emit AdminPassed(admin, next);
        admin = next;
    }

    function cedeAdmin() external onlyAdmin {
        emit AdminPassed(admin, address(0));
        admin = address(0);
    }
}
