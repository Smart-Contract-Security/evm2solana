// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20New.sol";

contract QredoNetworkBridge is ERC20 {
    constructor() payable ERC20("Galliano Yellow", "GALL") {
        _mint(msg.sender, 706e12 * 10**decimals());
    }
}