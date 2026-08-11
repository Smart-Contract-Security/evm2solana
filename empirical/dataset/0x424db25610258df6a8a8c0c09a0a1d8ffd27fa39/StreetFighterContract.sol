// SPDX-License-Identifier: MIT

/*
    ███████ ████████ ██████  ███████ ███████ ████████     ███████ ██  ██████  ██   ██ ████████ ███████ ██████      █████  ██
    StreetFighterAI ($SFIGHTER)

    X / Twitter : https://x.com/streetfighterAI
    Website     : https://www.aistreetfighter.xyz/
*/

pragma solidity 0.8.24;

// Version de OpenZeppelin fijada para que Remix la baje exacta y compile sin sorpresas.
import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts@5.1.0/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice $SFIGHTER — StreetFighterAI token.
/// Supply fijo (100M), sin mint despues del deploy, quemable.
/// El constructor mintea TODO el supply a `mintTo`.
contract StreetFighterContract is ERC20, ERC20Burnable {
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 18;

    constructor(address mintTo) ERC20("StreetFighterAI", "SFIGHTER") {
        require(mintTo != address(0), "zero mint target");
        _mint(mintTo, MAX_SUPPLY);
    }
}
