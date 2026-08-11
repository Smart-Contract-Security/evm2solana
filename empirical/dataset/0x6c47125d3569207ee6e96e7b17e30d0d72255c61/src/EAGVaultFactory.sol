// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {Initializable} from "./openzeppelin/5.6/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "./openzeppelin/5.6/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EAGWithdrawVault} from "./EAGWithdrawVault.sol";
import {IEAGVaultFactory} from "./interfaces/IEAGVaultFactory.sol";
import {IEAGVaultOperator} from "./interfaces/IEAGVaultOperator.sol";
import {ErrorsLib} from "./base/ErrorsLib.sol";
import {ConstantLib} from "./base/ConstantLib.sol";

/// @title EAGVaultFactory - Deterministic CREATE2 deployer for EAGWithdrawVault instances
/// @notice Uses sequential indices as salt for predictable vault addresses.
///         Only the authorized deployer (StakingRouter) can create new vaults.
///         The admin privilege is permanently renounced after the authorized deployer is set.
///
///         Upgradeable via TransparentUpgradeableProxy (OZ 5.x). Storage is segregated
///         into a single ERC-7201 namespaced slot (`eag.vault.factory.main`) so new
///         implementation versions can only grow the struct and never collide with
///         inherited OZ upgradeable modules (`Ownable`, `Ownable2Step`).
///
///         IMPORTANT: In a proxy context `address(this)` inside delegatecalls resolves
///         to the proxy address, so both `_initCodeHash()` and the `new EAGWithdrawVault`
///         CREATE2 deployment use the proxy address. `predictAddress` is therefore
///         stable across upgrades as long as:
///           - `type(EAGWithdrawVault).creationCode` does not change, AND
///           - the factory proxy address does not change.
///         Any new implementation MUST assert the same `_initCodeHash()` as the
///         previous version before being installed (see `DeployScript`).
contract EAGVaultFactory is Initializable, Ownable2StepUpgradeable, IEAGVaultFactory {
    // ═══════════════════════════════════════════
    //                VERSION
    // ═══════════════════════════════════════════

    /// @notice Human-readable implementation version. Bump on every new implementation
    ///         so operators can correlate on-chain state with a specific bytecode.
    uint64 public constant VERSION = 1;

    // ═══════════════════════════════════════════
    //        ERC-7201 NAMESPACED STORAGE
    // ═══════════════════════════════════════════

    /// @custom:storage-location erc7201:eag.vault.factory.main
    struct MainStorage {
        address admin;
        address authorizedDeployer;
        address initContributionFeeReceiver;
        address initServiceFeeReceiver;
        uint16 initServiceRate;
        uint16 initContributionRate;
        mapping(address => bool) realVaults;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("eag.vault.factory.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_SLOT =
        0x0b2e34ce76ecee6403a2da2262c954bc033da93ece4fe8add50e5465e6f69f00;

    function _storage() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_SLOT
        }
    }

    // ═══════════════════════════════════════════
    //                MODIFIERS
    // ═══════════════════════════════════════════

    modifier onlyAuthorizedDeployer() {
        require(msg.sender == _storage().authorizedDeployer, ErrorsLib.SenderNotAuthorizedDeployer());
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == _storage().admin, ErrorsLib.SenderNotAdmin());
        _;
    }

    // ═══════════════════════════════════════════
    //               CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @notice Implementation-contract constructor. Locks the implementation so it
    ///         cannot be initialized directly; all initialization must flow through
    ///         the proxy's `initialize(...)` call.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ═══════════════════════════════════════════
    //              INITIALIZER
    // ═══════════════════════════════════════════

    /// @notice One-time proxy initializer. Mirrors the legacy constructor arguments.
    /// @param initAdmin The one-time admin who sets the authorized deployer (renounced after)
    /// @param initOwner The contract owner (can update rates and fee receivers)
    /// @param initContributionFeeReceiver Default contribution fee receiver for new vaults
    /// @param initServiceFeeReceiver Default service fee receiver for new vaults
    /// @param initServiceRate Default service rate in basis points for new vaults
    /// @param initContributionRate Default contribution rate in basis points for new vaults
    function initialize(
        address initAdmin,
        address initOwner,
        address initContributionFeeReceiver,
        address initServiceFeeReceiver,
        uint16 initServiceRate,
        uint16 initContributionRate
    ) external initializer {
        require(initAdmin != address(0), ErrorsLib.ZeroArgument("admin"));
        require(initOwner != address(0), ErrorsLib.ZeroArgument("initOwner"));
        require(initContributionFeeReceiver != address(0), ErrorsLib.ZeroArgument("initContributionFeeReceiver"));
        require(initServiceFeeReceiver != address(0), ErrorsLib.ZeroArgument("initServiceFeeReceiver"));
        require(
            initServiceRate >= ConstantLib.MIN_SERVICE_RATE,
            ErrorsLib.InvalidRate(address(0), initServiceRate, initContributionRate)
        );
        require(
            initContributionRate >= ConstantLib.MIN_CONTRIBUTION_RATE,
            ErrorsLib.InvalidRate(address(0), initServiceRate, initContributionRate)
        );
        require(
            uint256(initServiceRate) + uint256(initContributionRate) <= ConstantLib.TOTAL_BASIS_POINTS,
            ErrorsLib.InvalidRate(address(0), initServiceRate, initContributionRate)
        );

        __Ownable_init(initOwner);
        __Ownable2Step_init();

        MainStorage storage $ = _storage();
        $.admin = initAdmin;
        $.initContributionFeeReceiver = initContributionFeeReceiver;
        $.initServiceFeeReceiver = initServiceFeeReceiver;
        $.initServiceRate = initServiceRate;
        $.initContributionRate = initContributionRate;
    }

    // ═══════════════════════════════════════════
    //             VIEW FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultFactory
    function admin() external view returns (address) {
        return _storage().admin;
    }

    /// @inheritdoc IEAGVaultFactory
    function contributionFeeReceiver() external view returns (address) {
        return _storage().initContributionFeeReceiver;
    }

    /// @inheritdoc IEAGVaultFactory
    function serviceFeeReceiver() external view returns (address) {
        return _storage().initServiceFeeReceiver;
    }

    /// @inheritdoc IEAGVaultFactory
    function serviceRate() external view returns (uint256) {
        return _storage().initServiceRate;
    }

    /// @inheritdoc IEAGVaultFactory
    function contributionRate() external view returns (uint256) {
        return _storage().initContributionRate;
    }

    /// @inheritdoc IEAGVaultFactory
    function authorizedDeployer() external view returns (address) {
        return _storage().authorizedDeployer;
    }

    /// @inheritdoc IEAGVaultFactory
    function isRealVault(address _vault) external view returns (bool) {
        return _storage().realVaults[_vault];
    }

    /// @inheritdoc IEAGVaultFactory
    function predictAddress(uint256 _index) external view returns (address) {
        return _computeAddress(bytes32(_index));
    }

    /// @notice Deterministic CREATE2 init-code hash used for vault address prediction.
    /// @dev Exposed publicly so off-chain tooling and upgrade scripts can assert that
    ///      a new factory implementation produces an identical init-code hash before
    ///      it is installed behind the proxy.
    function initCodeHash() external view returns (bytes32) {
        return _initCodeHash();
    }

    // ═══════════════════════════════════════════
    //        STATE-CHANGING FUNCTIONS
    // ═══════════════════════════════════════════

    /// @inheritdoc IEAGVaultFactory
    function deployVault(
        uint256 _index,
        address _owner,
        address _vaultOperator
    ) external onlyAuthorizedDeployer returns (address vault) {
        bytes32 salt = bytes32(_index);

        address predicted = _computeAddress(salt);

        require(predicted.code.length == 0, ErrorsLib.AddressAlreadyDeployed(predicted));

        vault = address(new EAGWithdrawVault{salt: salt}(address(this)));
        EAGWithdrawVault(payable(vault)).initialize(_owner, _vaultOperator);
        MainStorage storage $ = _storage();
        IEAGVaultOperator(_vaultOperator).initializeVaultData(
            vault,
            $.initServiceRate,
            $.initContributionRate,
            $.initServiceFeeReceiver,
            $.initContributionFeeReceiver
        );
        $.realVaults[vault] = true;

        emit VaultDeployed(_index, vault);
    }

    /// @inheritdoc IEAGVaultFactory
    function setAuthorizedDeployer(address _deployer) external onlyAdmin {
        require(_deployer != address(0), ErrorsLib.ZeroArgument("_deployer"));
        MainStorage storage $ = _storage();
        $.authorizedDeployer = _deployer;
        $.admin = address(0);
        emit AuthorizedDeployerSet(_deployer);
    }

    /// @inheritdoc IEAGVaultFactory
    function setInitialRates(uint16 _serviceRate, uint16 _contributionRate) external onlyOwner {
        MainStorage storage $ = _storage();
        require(
            _serviceRate >= ConstantLib.MIN_SERVICE_RATE,
            ErrorsLib.InvalidRate(address(0), _serviceRate, _contributionRate)
        );
        require(
            _contributionRate >= ConstantLib.MIN_CONTRIBUTION_RATE,
            ErrorsLib.InvalidRate(address(0), _serviceRate, _contributionRate)
        );
        require(
            uint256(_serviceRate) + uint256(_contributionRate) <= ConstantLib.TOTAL_BASIS_POINTS,
            ErrorsLib.InvalidRate(address(0), _serviceRate, _contributionRate)
        );
        require(
            _serviceRate != $.initServiceRate || _contributionRate != $.initContributionRate,
            ErrorsLib.RepeatedArgument()
        );
        $.initServiceRate = _serviceRate;
        $.initContributionRate = _contributionRate;
        emit InitialRatesChanged(_serviceRate, _contributionRate);
    }

    /// @inheritdoc IEAGVaultFactory
    function setInitialFeeReceivers(address _serviceFeeReceiver, address _contributionFeeReceiver) external onlyOwner {
        require(_serviceFeeReceiver != address(0), ErrorsLib.ZeroArgument("_serviceFeeReceiver"));
        require(_contributionFeeReceiver != address(0), ErrorsLib.ZeroArgument("_contributionFeeReceiver"));
        MainStorage storage $ = _storage();
        require(
            _serviceFeeReceiver != $.initServiceFeeReceiver || _contributionFeeReceiver != $.initContributionFeeReceiver,
            ErrorsLib.RepeatedArgument()
        );
        $.initServiceFeeReceiver = _serviceFeeReceiver;
        $.initContributionFeeReceiver = _contributionFeeReceiver;
        emit InitialFeeReceiversChanged(_serviceFeeReceiver, _contributionFeeReceiver);
    }

    // ═══════════════════════════════════════════
    //             INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Compute the CREATE2 init-code hash for EAGWithdrawVault instances deployed by this factory
    /// @dev Factory address is the only constructor argument; resulting hash is deterministic and
    ///      identical for every index, so both `predictAddress` and `deployVault` share it.
    function _initCodeHash() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(type(EAGWithdrawVault).creationCode, abi.encode(address(this))));
    }

    /// @notice Compute the CREATE2 address for a given salt using this factory's init-code hash
    /// @param _salt The CREATE2 salt (typically `bytes32(_index)`)
    function _computeAddress(bytes32 _salt) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), _salt, _initCodeHash()
        )))));
    }
}
