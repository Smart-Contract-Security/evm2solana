// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract WrappedEver is ERC20 {
    IERC20 immutable public oldToken;
    address constant public wrapper = 0xF59592B00416fAa0d7EA2Fc7909Be5222e18a482;

    constructor(IERC20 _oldToken) ERC20("Swap WEVER", "s2WEVER") {
        oldToken = _oldToken;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function wrap(uint amount) external {
        require (msg.sender == wrapper, "Only wrapper");
        require(oldToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        _mint(msg.sender, amount);
    }

    function unwrap(uint amount) external {
        _burn(msg.sender, amount);
        oldToken.transfer(msg.sender, amount);
    }
}
