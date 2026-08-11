// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @notice Push-based USDC-denominated price oracle. Engine feeder pushes
/// prices in batches; reads only revert on UnsetPrice (the token was never
/// pushed at all). Staleness is not enforced on-chain — every money-moving
/// path in the Vault (settle, rebalance) pushes fresh prices in the same
/// transaction, so a staleness check would only ever fire on read-only views
/// like pricePerShare(). The dashboard reads from QuestDB snapshots, not
/// live oracle reads, so silent-stale prices on views are an acceptable
/// tradeoff for contract simplicity. See REFACTOR_PLAN §1.9.
contract Oracle is AccessControl, IOracle {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant FEEDER_ROLE = keccak256("FEEDER_ROLE");

    /// @dev priceUSDC is scaled to USDC decimals (1e6) per *whole* token —
    /// e.g. ETH at $3500.00 is stored as 3_500_000_000.
    mapping(address => PriceData) private _prices;

    constructor(address admin, address feeder) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        _grantRole(FEEDER_ROLE, feeder);
        emit FeederSet(feeder);
    }

    function setPrice(address[] calldata tokens, uint128[] calldata prices) external onlyRole(FEEDER_ROLE) {
        if (tokens.length != prices.length) revert LengthMismatch();
        uint64 ts = uint64(block.timestamp);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (prices[i] == 0) revert ZeroPrice(tokens[i]);
            PriceData storage p = _prices[tokens[i]];
            p.priceUSDC = prices[i];
            p.updatedAt = ts;
            emit PriceUpdated(tokens[i], prices[i], ts);
        }
    }

    function getPrice(address token) external view returns (uint256) {
        PriceData memory p = _prices[token];
        if (p.updatedAt == 0) revert UnsetPrice(token);
        return uint256(p.priceUSDC);
    }

    function getPriceData(address token) external view returns (PriceData memory) {
        return _prices[token];
    }

    function setFeeder(address feeder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEEDER_ROLE, feeder);
        emit FeederSet(feeder);
    }

    function revokeFeeder(address feeder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(FEEDER_ROLE, feeder);
    }
}
