// SPDX-License-Identifier: Unlicense
// All Rights Reserved © Yield
pragma solidity ^0.8.30;

import { AaveV3Gateway } from "src/aave/AaveV3Gateway.sol";
import { IPool } from "src/aave/interfaces/IPool.sol";

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AaveV3GatewayFactory
/// @notice Deploys one {@link AaveV3Gateway} per underlying asset using the beacon proxy pattern.
/// @dev
/// - Uses {UpgradeableBeacon} so all deployed {BeaconProxy} instances share an implementation.
/// - Enforces a single gateway per `asset` via {gatewayOf}.
/// - Role-gated deployment via {DEPLOYER_ROLE}.
contract AaveV3GatewayFactory is AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Thrown when a required address parameter is the zero address.
    error ZeroAddress();

    /// @notice Thrown when attempting to deploy a gateway for an asset that already has one.
    error AlreadyDeployed();

    /// @notice Thrown when deadShares is zero.
    error ZeroDeadShares();

    /// @notice Emitted when a new gateway is deployed for an asset.
    /// @param asset The underlying ERC20 asset the gateway wraps.
    /// @param gateway The deployed beacon proxy address (the gateway).
    /// @param aToken The Aave aToken corresponding to `asset` in `pool`.
    /// @param pool The Aave Pool used by the gateway.
    event GatewayDeployed(address indexed asset, address indexed gateway, address indexed aToken, address pool);

    /// @notice Role that is allowed to deploy new gateways.
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /// @notice The upgradeable beacon shared by all deployed gateway proxies.
    /// @dev Immutable after construction.
    UpgradeableBeacon public immutable BEACON;

    /// @notice Maps an underlying asset to its deployed gateway proxy address.
    /// @dev If `gatewayOf[asset] == address(0)`, no gateway has been deployed for that asset yet.
    mapping(address asset => address gateway) public gatewayOf;

    /// @notice Constructs the factory and deploys the beacon.
    /// @dev
    /// Grants:
    /// - {DEFAULT_ADMIN_ROLE} to `admin`
    /// - {DEPLOYER_ROLE} to `initialDeployer` if nonzero, otherwise to `admin`
    /// Then deploys the beacon owned by `beaconOwner`.
    /// @param implementation The initial implementation used by the beacon (AaveV3Gateway logic contract).
    /// @param beaconOwner The owner of the beacon (controls implementation upgrades).
    /// @param admin The AccessControl admin for this factory.
    /// @param initialDeployer Optional deployer; if zero, defaults to `admin`.
    constructor(address implementation, address beaconOwner, address admin, address initialDeployer) {
        if (implementation == address(0)) revert ZeroAddress();
        if (beaconOwner == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        address deployer = initialDeployer;
        if (deployer == address(0)) deployer = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, deployer);

        BEACON = new UpgradeableBeacon(implementation, beaconOwner);
    }

    /// @notice Deploys a new beacon proxy gateway for `asset` and initializes it.
    /// @dev
    /// Requirements:
    /// - Caller must have {DEPLOYER_ROLE}.
    /// - `asset`, `pool`, `aToken`, and `gatewayAdmin` must be nonzero addresses.
    /// - A gateway must not already exist for `asset` (see {gatewayOf}).
    /// - `deadShares` must be nonzero.
    ///
    /// Initialization:
    /// Calls {AaveV3Gateway.initialize} on the newly deployed proxy using `abi.encodeCall`.
    /// After deployment, pulls `deadShares` of `asset` from the caller, approves the gateway,
    /// and calls {AaveV3Gateway.deposit} minting shares to `address(0)` to prevent inflation attacks.
    ///
    /// Emits {GatewayDeployed} on success.
    /// @param asset The underlying ERC20 asset to be managed by the gateway.
    /// @param name The ERC20 name for the gateway shares
    /// @param symbol The ERC20 symbol for the gateway shares token.
    /// @param pool The Aave Pool used for deposit/withdraw interactions.
    /// @param aToken The corresponding aToken for `asset` in `pool`.
    /// @param gatewayAdmin The admin/owner role address used by the deployed gateway (passed into initialize).
    /// @param referralCode The referral code forwarded to the gateway for deposits (if used by the gateway).
    /// @param deadShares Amount of assets to deposit as dead shares (minted to address(0)).
    /// @return gateway The deployed gateway proxy address.
    function deployGateway(
        IERC20 asset,
        string memory name,
        string memory symbol,
        IPool pool,
        IERC20 aToken,
        address gatewayAdmin,
        uint16 referralCode,
        uint256 deadShares
    )
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address)
    {
        address assetAddr = address(asset);
        if (assetAddr == address(0)) revert ZeroAddress();
        if (address(pool) == address(0)) revert ZeroAddress();
        if (address(aToken) == address(0)) revert ZeroAddress();
        if (gatewayAdmin == address(0)) revert ZeroAddress();
        if (gatewayOf[assetAddr] != address(0)) revert AlreadyDeployed();
        if (deadShares == 0) revert ZeroDeadShares();

        address gateway;
        {
            bytes memory initData = abi.encodeCall(
                AaveV3Gateway.initialize, (asset, name, symbol, pool, aToken, gatewayAdmin, referralCode)
            );
            gateway = address(new BeaconProxy(address(BEACON), initData));
        }

        gatewayOf[assetAddr] = gateway;
        emit GatewayDeployed(assetAddr, gateway, address(aToken), address(pool));

        asset.safeTransferFrom(msg.sender, address(this), deadShares);
        asset.forceApprove(gateway, deadShares);
        AaveV3Gateway(gateway).deposit(deadShares, address(0xdead));

        return gateway;
    }
}
