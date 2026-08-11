// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PawnTaxEngine} from "./PawnTaxEngine.sol";

abstract contract PawnRescue is PawnTaxEngine {
    event RescueETH(address indexed to, uint256 amount);
    event RescueTokens(address indexed token, address indexed to, uint256 amount);
    event ManualSwap(uint256 swapped, uint256 ethRouted);

    function rescuePawnETH() external onlyOwner {
        require(!tradingOpen, "disabled after launch");
        uint256 bal = address(this).balance;
        require(bal > 0, "no ETH");
        emit RescueETH(owner(), bal);
        (bool ok,) = payable(owner()).call{value: bal}("");
        require(ok, "transfer failed");
    }

    function rescuePawnTokens(address token, uint256 amount) external onlyOwner {
        if (token == address(0) || token == address(this)) {
            require(!tradingOpen, "disabled after launch");
            uint256 bal = _balances[address(this)];
            require(amount > 0 && bal >= amount, "bad amount");
            _balances[address(this)] -= amount;
            _balances[owner()] += amount;
            emit Transfer(address(this), owner(), amount);
            emit RescueTokens(address(this), owner(), amount);
        } else {
            emit RescueTokens(token, owner(), amount);
            IERC20(token).transfer(owner(), amount);
        }
    }

    function manualSwap(uint256 amount) external onlyOwner {
        uint256 toSwap = _min(amount, _min(_balances[address(this)], _maxTaxSwap));
        require(toSwap > 0, "nothing to swap");
        _swapTokensForEth(toSwap);
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) _routeTaxETH(ethBal);
        emit ManualSwap(toSwap, ethBal);
    }
}
