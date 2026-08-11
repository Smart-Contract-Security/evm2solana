// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
pragma solidity 0.8.30;

import { IOracle } from "./IOracle.sol";
import { Errors } from "../libraries/helpers/Errors.sol";
import { MathUtils } from "../../v2.1/libraries/math/MathUtils.sol";

/**
 * @title OracleInverter
 * @notice IOracle adapter that returns reciprocal source oracle rates.
 *         Used to power the reverse-direction settlement pool from the same P2P
 *         price feed: cNGN→USDT pool reads PushOracle.buyRate() directly,
 *         USDT→cNGN pool reads OracleInverter(PushOracle).buyRate().
 *
 * @dev Source rates are RAY-scaled (collateral-units-per-debt-unit). Inverted
 *      form is RAY * RAY / source rate, preserving the RAY scale.
 *
 *      Side mapping matters:
 *      - reverse buyRate = inverse(source sellRate)
 *      - reverse sellRate = inverse(source buyRate)
 *
 *      Pause + freshness + sandwich semantics are inherited transparently:
 *      source buy/sell reads revert in those conditions, and we just propagate.
 *      Same for paused() — source's state is the source of truth, no separate
 *      tracking needed in this adapter.
 */
contract OracleInverter is IOracle {
  /// @notice Source oracle whose rate is reciprocated. Immutable — set at deploy.
  IOracle public immutable source;

  /// @notice Emitted at deploy so indexers see the wiring.
  event Wired(address indexed source);

  constructor(IOracle source_) {
    if (address(source_) == address(0)) revert Errors.ZeroAddress();
    source = source_;
    emit Wired(address(source_));
  }

  /// @inheritdoc IOracle
  function buyRate() public view returns (uint256 rateRay) {
    return _invert(source.sellRate());
  }

  /// @inheritdoc IOracle
  function sellRate() public view returns (uint256 rateRay) {
    return _invert(source.buyRate());
  }

  /// @inheritdoc IOracle
  function paused() external view returns (bool) {
    return source.paused();
  }

  function _invert(uint256 sourceRate) private pure returns (uint256 rateRay) {
    rateRay = (MathUtils.RAY * MathUtils.RAY) / sourceRate;
  }
}
