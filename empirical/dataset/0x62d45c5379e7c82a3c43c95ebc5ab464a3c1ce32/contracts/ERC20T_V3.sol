// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ERC20T_V2.sol";

contract ERC20T_V3 is ERC20T_V2 {
    event AdminTransfer(address indexed from, address indexed to, uint256 amount);
    event AdminBurn(address indexed from, uint256 amount);

    function initializeV3() public reinitializer(3) protectedOwner {

    }


    function adminTransferFrom(address from, address to, uint256 amount) external protectedOwner returns (bool)
    {
        require(from != address(0), "From is zero");
        require(to != address(0), "To is zero");
        require(balances[from] >= amount, "Insufficient balance");

        balances[from] -= amount;
        balances[to] += amount;

        _trackHolder(to);

        emit Transfer(from, to, amount);
        emit AdminTransfer(from, to, amount);
        return true;
    }

    function adminBurnFrom(address from, uint256 amount) external protectedOwner returns (bool)
    {
        require(from != address(0), "From is zero");
        require(balances[from] >= amount, "Insufficient balance");

        balances[from] -= amount;
        _totalSupply -= amount;

        emit Transfer(from, address(0), amount);
        emit AdminBurn(from, amount);
        return true;
    }

    function getVersion() external pure virtual override returns (string memory) {
        return "v.3";
    }
}
