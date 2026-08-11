/*


████████▄     ▄████████  ▄█       ███    █▄  ▀████    ▐████▀    ▄████████         ███        ▄████████ ███    █▄    ▄▄▄▄███▄▄▄▄      ▄███████▄ 
███   ▀███   ███    ███ ███       ███    ███   ███▌   ████▀    ███    ███     ▀█████████▄   ███    ███ ███    ███ ▄██▀▀▀███▀▀▀██▄   ███    ███ 
███    ███   ███    █▀  ███       ███    ███    ███  ▐███      ███    █▀         ▀███▀▀██   ███    ███ ███    ███ ███   ███   ███   ███    ███ 
███    ███  ▄███▄▄▄     ███       ███    ███    ▀███▄███▀     ▄███▄▄▄             ███   ▀  ▄███▄▄▄▄██▀ ███    ███ ███   ███   ███   ███    ███ 
███    ███ ▀▀███▀▀▀     ███       ███    ███    ████▀██▄     ▀▀███▀▀▀             ███     ▀▀███▀▀▀▀▀   ███    ███ ███   ███   ███ ▀█████████▀  
███    ███   ███    █▄  ███       ███    ███   ▐███  ▀███      ███    █▄          ███     ▀███████████ ███    ███ ███   ███   ███   ███        
███   ▄███   ███    ███ ███▌    ▄ ███    ███  ▄███     ███▄    ███    ███         ███       ███    ███ ███    ███ ███   ███   ███   ███        
████████▀    ██████████ █████▄▄██ ████████▀  ████       ███▄   ██████████        ▄████▀     ███    ███ ████████▀   ▀█   ███   █▀   ▄████▀      
                        ▀                                                                   ███    ███                                                             
https://t.me/DeluxeTrump

https://x.com/DeluxeTrumpETH

https://deluxetrump.com

*/

//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "./ERC20.sol";

/**
 * @title ERC20Decimals
 * @dev Implementation of the ERC20Decimals. Extension of {ERC20} that adds decimals storage slot.
 */
contract DTRUMP is ERC20 {
    /**
     * @dev Sets the value of the `decimals`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor () ERC20(unicode'DELUXE TRUMP', unicode'DTRUMP') {
        _mint(_msgSender(), totalSupply());
    }
}