// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProtocolPhase} from "./ProtocolPhase.sol";
import {IProtocolRegistry} from "./IProtocolRegistry.sol";

/// @title ProtocolRegistry
/// @notice Single source of truth for the protocol's global state and module
/// addresses. Every other contract reads this; nothing else holds the phase.
///
/// Design notes
/// - One-way phase machine (whitepaper §09).
/// - Module addresses settable ONCE each; subsequent writes revert. This is
///   what enforces "HatCard.mint is callable only by PackSale" without
///   needing setters on every consumer.
/// - Ownership uses Ownable2Step so a stuck/lost key can't lose the registry.
contract ProtocolRegistry is Ownable2Step, IProtocolRegistry {
    using ProtocolPhase for ProtocolPhase.Phase;

    ProtocolPhase.Phase private _phase;

    address public override packSale;
    address public override entropy;
    address public override hatCard;
    address public override hatToken;
    address public override hatTrickHook;
    address public override prizeVault;
    address public override matchOracle;
    address public override scoringEngine;
    address public override treasury;

    event PhaseAdvanced(ProtocolPhase.Phase indexed from, ProtocolPhase.Phase indexed to);
    event ModuleSet(bytes32 indexed key, address indexed module);

    error ModuleAlreadySet(bytes32 key);
    error ZeroAddress();

    constructor(address initialOwner) Ownable(initialOwner) {
        _phase = ProtocolPhase.Phase.PRESALE;
    }

    // ─── phase ───────────────────────────────────────────────────────────

    function phase() external view override returns (ProtocolPhase.Phase) {
        return _phase;
    }

    function isAtOrAfter(ProtocolPhase.Phase p) external view override returns (bool) {
        return uint8(_phase) >= uint8(p);
    }

    function isBefore(ProtocolPhase.Phase p) external view override returns (bool) {
        return uint8(_phase) < uint8(p);
    }

    /// @notice Advance the protocol phase. One-way; reverts if not forward.
    function advanceTo(ProtocolPhase.Phase to) external onlyOwner {
        ProtocolPhase._requireForward(_phase, to);
        emit PhaseAdvanced(_phase, to);
        _phase = to;
    }

    // ─── modules (settable once) ─────────────────────────────────────────

    function setPackSale(address a) external onlyOwner    { _setOnce(packSale,     a, "packSale");     packSale     = a; }
    function setEntropy(address a) external onlyOwner     { _setOnce(entropy,      a, "entropy");      entropy      = a; }
    function setHatCard(address a) external onlyOwner     { _setOnce(hatCard,      a, "hatCard");      hatCard      = a; }
    function setHatToken(address a) external onlyOwner    { _setOnce(hatToken,     a, "hatToken");     hatToken     = a; }
    function setHatTrickHook(address a) external onlyOwner{ _setOnce(hatTrickHook, a, "hatTrickHook");hatTrickHook = a; }
    function setPrizeVault(address a) external onlyOwner  { _setOnce(prizeVault,   a, "prizeVault");   prizeVault   = a; }
    function setMatchOracle(address a) external onlyOwner { _setOnce(matchOracle,  a, "matchOracle");  matchOracle  = a; }
    function setScoringEngine(address a) external onlyOwner{_setOnce(scoringEngine,a,"scoringEngine");scoringEngine= a; }
    function setTreasury(address a) external onlyOwner    { _setOnce(treasury,     a, "treasury");     treasury     = a; }

    function _setOnce(address current, address newAddr, bytes32 key) internal {
        if (newAddr == address(0)) revert ZeroAddress();
        if (current != address(0)) revert ModuleAlreadySet(key);
        emit ModuleSet(key, newAddr);
    }
}
