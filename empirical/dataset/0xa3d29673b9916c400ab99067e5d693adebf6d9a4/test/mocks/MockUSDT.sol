// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title MockUSDT
/// @notice Mirrors Tether's non-standard ERC20 ABI: `transfer` and `transferFrom`
///         return nothing (not `bool`). Used to verify SafeERC20 compatibility
///         in unit tests without requiring a mainnet fork.
/// @dev Deliberately does NOT inherit from `IERC20` (the interface declares
///      `bool` returns, which would break the void-return ABI we need to mimic).
contract MockUSDT {
    string public constant name = "Mock Tether USD";
    string public constant symbol = "USDT";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance();
    error InsufficientAllowance();

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @dev Note: no return value, matching real USDT.
    function transfer(address to, uint256 value) external {
        _transfer(msg.sender, to, value);
    }

    /// @dev Note: no return value, matching real USDT.
    function transferFrom(address from, address to, uint256 value) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        uint256 fromBal = balanceOf[from];
        if (fromBal < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = fromBal - value;
        }
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
