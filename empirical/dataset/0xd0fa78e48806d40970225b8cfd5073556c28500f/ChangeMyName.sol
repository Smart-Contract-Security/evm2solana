// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    ChangeMyName

    An experimental ERC-20 draft where anyone can change the token's
    name and ticker. Go to Etherscan, find this contract, and call
    setName() or setSymbol() with whatever you want. It's free.
*/

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract ChangeMyName is IERC20, IERC20Metadata {

    // Errors

    error InsufficientBalance(address from, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ZeroAddress();

    error NameTooLong();
    error NameTooShort();
    error NameHasBadCharacter(uint256 index);
    error SymbolTooLong();
    error SymbolTooShort();
    error SymbolHasBadCharacter(uint256 index);

    // Constants

    uint8   public constant decimals         = 18;
    uint256 public constant MAX_NAME_BYTES   = 64;
    uint256 public constant MAX_SYMBOL_BYTES = 16;

    // State

    string  private _name;
    string  private _symbol;
    uint256 public  immutable totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Events

    event NameChanged(address indexed by, string newName);
    event SymbolChanged(address indexed by, string newSymbol);

    // Constructor

    /// @dev All values are hardcoded. The full supply mints to the deployer.
    constructor() {
        _name   = "ChangeMyName";
        _symbol = "ChangeMyTicker";

        totalSupply = 420_694_200 * (10 ** uint256(decimals));
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // ─────────── Name and symbol changes (anyone, free) ───────────

    function setName(string calldata newName) external {
        _checkName(bytes(newName));
        _name = newName;
        emit NameChanged(msg.sender, newName);
    }

    function setSymbol(string calldata newSymbol) external {
        _checkSymbol(bytes(newSymbol));
        _symbol = newSymbol;
        emit SymbolChanged(msg.sender, newSymbol);
    }

    function setNameAndSymbol(string calldata newName, string calldata newSymbol) external {
        _checkName(bytes(newName));
        _checkSymbol(bytes(newSymbol));
        _name   = newName;
        _symbol = newSymbol;
        emit NameChanged(msg.sender, newName);
        emit SymbolChanged(msg.sender, newSymbol);
    }

    // Length-bounded, printable ASCII only (0x20–0x7E).
    // Blocks null bytes, control chars, and non-ASCII garbage on chain.
    function _checkName(bytes memory b) internal pure {
        if (b.length == 0) revert NameTooShort();
        if (b.length > MAX_NAME_BYTES) revert NameTooLong();
        for (uint256 i = 0; i < b.length; i++) {
            uint8 ch = uint8(b[i]);
            if (ch < 0x20 || ch > 0x7E) revert NameHasBadCharacter(i);
        }
    }

    function _checkSymbol(bytes memory b) internal pure {
        if (b.length == 0) revert SymbolTooShort();
        if (b.length > MAX_SYMBOL_BYTES) revert SymbolTooLong();
        for (uint256 i = 0; i < b.length; i++) {
            uint8 ch = uint8(b[i]);
            if (ch < 0x20 || ch > 0x7E) revert SymbolHasBadCharacter(i);
        }
    }

    // ─────────── ERC-20 metadata ───────────

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }

    // ─────────── ERC-20 core ───────────

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance(msg.sender, allowed, value);
            unchecked { allowance[from][msg.sender] = allowed - value; }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBal = balanceOf[from];
        if (fromBal < value) revert InsufficientBalance(from, fromBal, value);
        unchecked {
            balanceOf[from]  = fromBal - value;
            balanceOf[to]   += value;
        }
        emit Transfer(from, to, value);
    }

    // ─────────── Reject ETH ───────────

    receive() external payable { revert(); }
    fallback() external payable { revert(); }
}
