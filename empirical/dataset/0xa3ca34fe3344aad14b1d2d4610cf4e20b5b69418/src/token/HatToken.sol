// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHatToken} from "./IHatToken.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {ProtocolPhase} from "../protocol/ProtocolPhase.sol";
import {IGate} from "../gate/IGate.sol";
import {Errors} from "../util/Errors.sol";

/// $HAT — the protocol's fungible token. Standard ERC-20 with two
/// privileged mint paths and otherwise free burn. Socials:
///   https://www.hatworldcup.com
contract HatToken is ERC20, ERC20Permit, ERC20Burnable, Ownable, IHatToken {
    IProtocolRegistry public immutable registry;
    address public gate;

    event EmissionMinted(address indexed to, uint256 amount);
    event BurnToMintMinted(address indexed to, uint256 amount);
    event InitialMinted(address indexed to, uint256 amount);
    event GateSet(address indexed gate);

    error Denied();

    constructor(IProtocolRegistry _registry, address _owner)
        ERC20("HAT-TRICK", "HAT")
        ERC20Permit("HAT-TRICK")
        Ownable(_owner)
    {
        registry = _registry;
    }

    // ─── restricted mints ────────────────────────────────────────────────

    function mintEmission(address to, uint256 amount) external override {
        if (msg.sender != registry.prizeVault()) revert Errors.NotAuthorized();
        uint8 ph = uint8(registry.phase());
        if (ph < uint8(ProtocolPhase.Phase.TGE) || ph > uint8(ProtocolPhase.Phase.FULL_TIME)) {
            revert Errors.WrongPhase();
        }
        if (amount == 0) revert Errors.ZeroAmount();
        _mint(to, amount);
        emit EmissionMinted(to, amount);
    }

    function mintBurnToMint(address to, uint256 amount) external override {
        if (msg.sender != registry.hatCard()) revert Errors.NotAuthorized();
        if (uint8(registry.phase()) < uint8(ProtocolPhase.Phase.TGE)) revert Errors.WrongPhase();
        if (amount == 0) revert Errors.ZeroAmount();
        _mint(to, amount);
        emit BurnToMintMinted(to, amount);
    }

    // ─── admin ───────────────────────────────────────────────────────────

    function setGate(address g) external onlyOwner {
        gate = g;
        emit GateSet(g);
    }

    /// @notice Owner mint, pre-TGE only. Used at deploy time to seed the
    /// LP and any pre-launch allocations. Once the registry phase advances
    /// to TGE, this function is locked permanently — supply growth after
    /// that point is governed only by `mintEmission` (PrizeVault) and
    /// `mintBurnToMint` (HatCard).
    function mintInitial(address to, uint256 amount) external onlyOwner {
        if (uint8(registry.phase()) >= uint8(ProtocolPhase.Phase.TGE)) revert Errors.WrongPhase();
        if (amount == 0) revert Errors.ZeroAmount();
        _mint(to, amount);
        emit InitialMinted(to, amount);
    }

    // ─── ERC20 hook ──────────────────────────────────────────────────────

    function _update(address from, address to, uint256 value) internal override(ERC20) {
        address g = gate;
        if (g != address(0)) {
            if (IGate(g).denied(from)) revert Denied();
            if (IGate(g).denied(to))   revert Denied();
        }
        super._update(from, to, value);
    }

    // ─── burn (ERC20Burnable provides open burn/burnFrom) ────────────────

    function burn(uint256 amount) public override(ERC20Burnable, IHatToken) {
        ERC20Burnable.burn(amount);
    }

    function burnFrom(address from, uint256 amount) public override(ERC20Burnable, IHatToken) {
        ERC20Burnable.burnFrom(from, amount);
    }
}
