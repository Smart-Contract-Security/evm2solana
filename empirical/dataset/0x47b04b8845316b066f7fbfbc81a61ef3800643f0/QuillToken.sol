// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

// QUILL — the currency of the on-chain model economy.
// Used to inscribe generations permanently on-chain. Fixed supply, burnable,
// no minting after deployment, no owner.
// https://quill.computer

import "./AxiomEngine.sol";
import "./AxiomEngineLN.sol";

contract QuillComputer is ERC20, ERC20Burnable {

    constructor()
        ERC20("Quill","QUILL")
    {
        _mint(msg.sender, 1_000_000_000 * 1e18);
    }
}