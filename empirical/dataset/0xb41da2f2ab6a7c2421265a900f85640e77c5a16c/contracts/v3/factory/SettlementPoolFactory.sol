// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Textile, Inc.
pragma solidity 0.8.30;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISettlementPoolFactory } from "../interfaces/ISettlementPoolFactory.sol";
import { IOracle } from "../oracles/IOracle.sol";
import { Errors } from "../libraries/helpers/Errors.sol";
import { SettlementPool } from "../core/SettlementPool.sol";

/**
 * @title SettlementPoolFactory
 * @notice Deploys and tracks SettlementPool instances. One instance per
 *         (collateralAsset, debtAsset, params) tuple. Holds the global
 *         pause flag (Pausable) and ownership (Ownable2Step) that pools
 *         read for open gating and admin-sweep authorization.
 *
 * @dev Audit standards (v2.1, node.security):
 *      - OZ `Ownable2Step` — new owner must `acceptOwnership()` (audit L-04).
 *      - `renounceOwnership` overridden to revert (audit L-04).
 *      - OZ `Pausable` — standard `Paused`/`Unpaused` events; pool reads `paused()`.
 *      - Custom errors via shared `Errors.sol`.
 *      - All state-changing functions emit events.
 *      - Constructor validates inputs.
 */
contract SettlementPoolFactory is ISettlementPoolFactory, Ownable2Step, Pausable {
  /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
  //////////////////////////////////////////////////////////////*/

  /// @notice All pools deployed by this factory, in deploy order.
  address[] public pools;

  /// @notice True iff the address was deployed by this factory.
  mapping(address => bool) public isPool;

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event PoolDeployed(
    address indexed pool,
    address indexed oracle,
    address indexed collateralAsset,
    address debtAsset,
    uint256 buffer,
    uint256 floorFee,
    uint256 window,
    uint256 minPositionSize,
    uint256 minDepositSize
  );

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(address owner_) Ownable(owner_) {}

  /*//////////////////////////////////////////////////////////////
                          ADMIN: PAUSE
  //////////////////////////////////////////////////////////////*/

  /// @notice Halt new opens across all pools (closes always allowed).
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Resume new opens.
  function unpause() external onlyOwner {
    _unpause();
  }

  /*//////////////////////////////////////////////////////////////
                          ADMIN: DEPLOY
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a new SettlementPool. onlyOwner.
   * @param oracle Price feed (must implement IOracle).
   * @param collateralAsset Collateral ERC20.
   * @param debtAsset Debt ERC20.
   * @param buffer LTV cushion in RAY (e.g. 1e26 = 10%).
   * @param floorFee Floor fee in RAY (must be < buffer).
   * @param window Buffer-window in seconds (> 0).
   * @param minPositionSize Minimum D per open() (debt atomic units).
   * @param minDepositSize Minimum amount per deposit.
   * @return pool Address of the newly deployed SettlementPool.
   */
  function deployPool(
    IOracle oracle,
    IERC20 collateralAsset,
    IERC20 debtAsset,
    uint256 buffer,
    uint256 floorFee,
    uint256 window,
    uint256 minPositionSize,
    uint256 minDepositSize
  ) external onlyOwner returns (address pool) {
    SettlementPool deployed = new SettlementPool(
      oracle,
      collateralAsset,
      debtAsset,
      this,
      buffer,
      floorFee,
      window,
      minPositionSize,
      minDepositSize
    );
    pool = address(deployed);
    pools.push(pool);
    isPool[pool] = true;

    emit PoolDeployed(
      pool,
      address(oracle),
      address(collateralAsset),
      address(debtAsset),
      buffer,
      floorFee,
      window,
      minPositionSize,
      minDepositSize
    );
  }

  /*//////////////////////////////////////////////////////////////
                          ADMIN-LOSS GUARD
  //////////////////////////////////////////////////////////////*/

  /// @notice Disabled — prevents accidental admin loss to address(0).
  ///         Use `transferOwnership` (Ownable2Step) for legitimate handoff.
  function renounceOwnership() public view override onlyOwner {
    revert Errors.RenounceDisabled();
  }

  /*//////////////////////////////////////////////////////////////
                              VIEWS
  //////////////////////////////////////////////////////////////*/

  /// @notice Number of pools ever deployed by this factory.
  function poolCount() external view returns (uint256) {
    return pools.length;
  }

  /// @inheritdoc ISettlementPoolFactory
  /// @dev Disambiguation: ISettlementPoolFactory + Pausable both declare paused().
  function paused() public view override(ISettlementPoolFactory, Pausable) returns (bool) {
    return Pausable.paused();
  }

  /// @inheritdoc ISettlementPoolFactory
  /// @dev Disambiguation: ISettlementPoolFactory + Ownable both declare owner().
  function owner() public view override(ISettlementPoolFactory, Ownable) returns (address) {
    return Ownable.owner();
  }
}
