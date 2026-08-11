// SPDX-License-Identifier: MIT

/*
/info Football moments. Digital collectibles. Own the plays that define the game.
/X https://x.com/onsideclub_xyz
/web https://www.onsideclub.xyz/
*/

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address, uint, uint, uint, address, uint
    ) external payable returns (uint, uint, uint);
}

interface IUniswapV2Factory {
    function createPair(address, address) external returns (address);
}

contract onside is ERC20 {
    address private immutable _deployer;
    IUniswapV2Router02 private constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public pair;

    constructor() ERC20("Onside Club", "ONSIDE") {
        _deployer = msg.sender;
        _mint(address(this), 500_000_000 ether);
    }

    function enableTrading() external payable {
        require(msg.sender == _deployer && msg.value > 0);
        
        pair = IUniswapV2Factory(ROUTER.factory()).createPair(address(this), ROUTER.WETH());
        
        uint256 bal = balanceOf(address(this));
        _approve(address(this), address(ROUTER), bal);
        
        ROUTER.addLiquidityETH{value: msg.value}(
            address(this), bal, 0, 0, msg.sender, block.timestamp + 600
        );
    }

    receive() external payable {}
}