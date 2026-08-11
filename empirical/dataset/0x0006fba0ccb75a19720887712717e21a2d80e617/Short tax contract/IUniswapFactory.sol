// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) 
        external 
        view 
        returns 
        (address pair);
    function allPairs(uint) 
        external 
        view 
        returns 
        (address pair);
    function allPairsLength() 
        external 
        view 
        returns 
        (uint);
    function feeTo() 
        external 
        view 
        returns 
        (address);
    function feeToSetter() 
        external 
        view 
        returns 
        (address);
    
}