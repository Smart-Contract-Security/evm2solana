// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title vXVO Presale Token
/// @notice ERC-20 placeholder for the XVO Ledger native coin. Bridge-compatible
///         with capped mint and role-based access control.
/// @dev Uses 6 decimals to match the XVO Ledger L1 (1 XVO = 1,000,000 drops),
///      giving a 1:1 parity between the ERC-20 base unit and an L1 drop — no
///      conversion multiplier needed at the bridge.
contract VXVO is ERC20, ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// 10B vXVO at 6 decimals = 10^10 * 10^6 base units.
    uint256 public constant MAX_SUPPLY = 10_000_000_000 * 10 ** 6;

    uint256 public cumulativeBurned;

    bool public redemptionEnabled;

    /// Minimum redeem = 1 base unit = 1 L1 drop (1:1 parity at 6 decimals).
    uint256 public constant MIN_REDEEM = 1;

    event TokensBurned(address indexed user, uint256 amount);
    event RedemptionToggled(bool enabled);

    constructor(address admin) ERC20("vXVO Presale Token", "vXVO") {
        require(admin != address(0), "admin zero address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _mint(admin, MAX_SUPPLY);
    }

    /// @notice 6 decimals — matches the XVO Ledger L1 native asset.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "cap exceeded");
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    function redeem(uint256 amount) external whenNotPaused {
        require(redemptionEnabled, "redemption disabled");
        require(amount >= MIN_REDEEM, "below min redeem");
        _burn(msg.sender, amount);
        cumulativeBurned += amount;
        emit TokensBurned(msg.sender, amount);
    }

    function toggleRedemption(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        redemptionEnabled = enabled;
        emit RedemptionToggled(enabled);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
