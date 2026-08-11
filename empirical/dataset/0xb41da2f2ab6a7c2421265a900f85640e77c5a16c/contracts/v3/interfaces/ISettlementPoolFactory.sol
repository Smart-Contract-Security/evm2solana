// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
// This smart contract is part of the Textile Protocol (Settlement v3).
pragma solidity 0.8.30;

/**
 * @title ISettlementPoolFactory
 * @notice Minimal interface SettlementPool reads from its parent factory.
 *         Factory implements `paused()` (OZ Pausable) and `owner()` (OZ Ownable2Step)
 *         in commit [03]. Tests use a `MockFactory` that implements the same surface.
 */
interface ISettlementPoolFactory {
  function paused() external view returns (bool);
  function owner() external view returns (address);
}
