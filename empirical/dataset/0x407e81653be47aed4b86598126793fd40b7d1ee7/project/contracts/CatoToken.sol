// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CatoToken is ERC20, Ownable {
    error CatoToken_ZeroAddress();
    error CatoToken_NotMinter();
    error CatoToken_MinterLocked();

    address public minter;
    bool public minterLocked;

    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event MinterLocked(address indexed minter);

    constructor(address initialOwner) ERC20("System of Unrecoverable Mass", "SUM") Ownable(initialOwner) {
        if (initialOwner == address(0)) revert CatoToken_ZeroAddress();
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert CatoToken_NotMinter();
        _;
    }

    function setMinter(address newMinter) external onlyOwner {
        if (minterLocked) revert CatoToken_MinterLocked();
        if (newMinter == address(0)) revert CatoToken_ZeroAddress();

        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }

    function lockMinter() external onlyOwner {
        if (minter == address(0)) revert CatoToken_ZeroAddress();
        minterLocked = true;
        emit MinterLocked(minter);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burnFromByMinter(address account, uint256 amount) external onlyMinter {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
