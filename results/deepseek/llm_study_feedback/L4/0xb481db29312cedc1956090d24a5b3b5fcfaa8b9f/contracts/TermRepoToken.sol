// SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

import {ExponentialNoError} from "./lib/ExponentialNoError.sol";
import {TermRepoTokenConfig} from "./lib/TermRepoTokenConfig.sol";
import {TermContractsPausable} from "./lib/TermContractsPausable.sol";
import {ITermRepoCollateralManager} from "./interfaces/ITermRepoCollateralManager.sol";
import {ITermRepoToken} from "./interfaces/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/ITermRepoServicer.sol";
import {ITermRepoTokenErrors} from "./interfaces/ITermRepoTokenErrors.sol";
import {ITermEventEmitter} from "./interfaces/ITermEventEmitter.sol";
import {Versionable} from "./lib/Versionable.sol";

contract TermRepoToken is
    ExponentialNoError,
    ITermRepoTokenErrors,
    ITermRepoToken,
    TermContractsPausable,
    Versionable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEVOPS_ROLE = keccak256("DEVOPS_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");

    uint8 internal decimalPlaces;
    bool internal termContractPaired;
    bool public mintingPaused;
    bool public burningPaused;
    uint256 public redemptionValue;
    bytes32 public termRepoId;
    uint256 public mintExposureCap;
    TermRepoTokenConfig public config;
    ITermEventEmitter internal emitter;

    // ERC20 state
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    // AccessControl state
    mapping(bytes32 => mapping(address => bool)) private _roles;

    // UUPS state
    address private _implementation;

    // ERC20Permit state
    mapping(address => uint256) private _nonces;
    bytes32 private constant _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private _domainSeparator;

    // Initializable state
    bool private _initialized;
    bool private _initializing;

    modifier whileMintingNotPaused() {
        if (mintingPaused) {
            revert TermRepoTokenMintingPaused();
        }
        _;
    }

    modifier whileBurningNotPaused() {
        if (burningPaused) {
            revert TermRepoTokenBurningPaused();
        }
        _;
    }

    modifier notTermContractPaired() {
        if (termContractPaired) {
            revert AlreadyTermContractPaired();
        }
        termContractPaired = true;
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: missing role");
        _;
    }

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }

    constructor() {
        _disableInitializers();
    }

    function _disableInitializers() internal {
        _initialized = true;
    }

    function initialize(
        string calldata termRepoId_,
        string calldata name_,
        string calldata symbol_,
        uint8 decimalPlaces_,
        uint256 redemptionValue_,
        uint256 mintExposureCap_,
        address termInitializer_,
        TermRepoTokenConfig calldata config_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name_)),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));

        _grantRole(INITIALIZER_ROLE, termInitializer_);

        decimalPlaces = decimalPlaces_;
        redemptionValue = redemptionValue_;
        require(
            config_.purchaseToken != address(0) &&
                config_.termRepoCollateralManager != address(0) &&
                config_.termRepoServicer != address(0),
            "zero address in config"
        );
        config = config_;

        termRepoId = keccak256(abi.encodePacked(termRepoId_));

        mintExposureCap = mintExposureCap_;

        mintingPaused = false;

        termContractPaired = false;
    }

    function pairTermContracts(
        address termRepoServicer_,
        ITermEventEmitter emitter_,
        address devopsMultisig_,
        address adminWallet_
    ) external onlyRole(INITIALIZER_ROLE) notTermContractPaired {
        emitter = emitter_;

        _grantRole(ADMIN_ROLE, adminWallet_);
        _grantRole(MINTER_ROLE, termRepoServicer_);
        _grantRole(BURNER_ROLE, termRepoServicer_);
        _grantRole(DEVOPS_ROLE, devopsMultisig_);

        emitter.emitTermRepoTokenInitialized(
            termRepoId,
            address(this),
            redemptionValue
        );
    }

    function resetMintExposureCap(
        uint256 mintExposureCap_
    ) external onlyRole(ADMIN_ROLE) {
        mintExposureCap = mintExposureCap_;
    }

    function totalRedemptionValue() external view returns (uint256) {
        uint256 totalValue = truncate(
            mul_(
                Exp({mantissa: totalSupply() * expScale}),
                Exp({mantissa: redemptionValue})
            )
        );
        return totalValue;
    }

    function burn(
        address account,
        uint256 amount
    ) external onlyRole(BURNER_ROLE) whileBurningNotPaused whileTermContractsNotPaused(ITermRepoServicer(config.termRepoServicer).termController()) {
        _burn(account, amount);
        mintExposureCap += amount;
    }

    function burnAndReturnValue(
        address account,
        uint256 amount
    )
        external
        onlyRole(BURNER_ROLE)
        whileBurningNotPaused
        whileTermContractsNotPaused(ITermRepoServicer(config.termRepoServicer).termController())
        returns (uint256)
    {
        _burn(account, amount);
        mintExposureCap += amount;
        uint256 valueBurned = truncate(
            mul_(
                Exp({mantissa: amount * expScale}),
                Exp({mantissa: redemptionValue})
            )
        );
        return valueBurned;
    }

    function mintRedemptionValue(
        address account,
        uint256 redemptionAmount
    )
        external
        whileMintingNotPaused
        whileTermContractsNotPaused(ITermRepoServicer(config.termRepoServicer).termController())
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        uint256 numTokens = truncate(
            div_(
                Exp({mantissa: redemptionAmount * expScale}),
                Exp({mantissa: redemptionValue})
            )
        );
        _mint(account, numTokens);
        return numTokens;
    }

    function mintTokens(
        address account,
        uint256 numTokens
    )
        external
        whileMintingNotPaused
        whileTermContractsNotPaused(ITermRepoServicer(config.termRepoServicer).termController())
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        _mint(account, numTokens);
        uint256 redemptionValueMinted = truncate(
            mul_(
                Exp({mantissa: numTokens * expScale}),
                Exp({mantissa: redemptionValue})
            )
        );
        return redemptionValueMinted;
    }

    function decrementMintExposureCap(
        uint256 supplyMinted
    ) external onlyRole(MINTER_ROLE) {
        if (supplyMinted > mintExposureCap) {
            revert MintExposureCapExceeded();
        }
        mintExposureCap -= supplyMinted;
    }

    function decimals() public view virtual returns (uint8) {
        return decimalPlaces;
    }

    function getCollateralRequirements()
        external
        view
        returns (
            address[] memory collateralTokens,
            uint256[] memory maintenanceRatios
        )
    {
        ITermRepoCollateralManager collateralManager = ITermRepoCollateralManager(
                config.termRepoCollateralManager
            );
        uint256 numOfCollateralTokens = uint256(
            collateralManager.numOfAcceptedCollateralTokens()
        );
        collateralTokens = new address[](numOfCollateralTokens);
        maintenanceRatios = new uint256[](numOfCollateralTokens);
        for (uint256 i = 0; i < numOfCollateralTokens; ++i) {
            collateralTokens[i] = collateralManager.collateralTokens(i);
            maintenanceRatios[i] = collateralManager
                .maintenanceCollateralRatios(collateralTokens[i]);
        }
    }

    function pauseMinting() external onlyRole(ADMIN_ROLE) {
        mintingPaused = true;
        emitter.emitTermRepoTokenMintingPaused(termRepoId);
    }

    function unpauseMinting() external onlyRole(ADMIN_ROLE) {
        mintingPaused = false;
        emitter.emitTermRepoTokenMintingUnpaused(termRepoId);
    }

    function pauseBurning() external onlyRole(ADMIN_ROLE) {
        burningPaused = true;
        emitter.emitTermRepoTokenBurningPaused(termRepoId);
    }

    function unpauseBurning() external onlyRole(ADMIN_ROLE) {
        burningPaused = false;
        emitter.emitTermRepoTokenBurningUnpaused(termRepoId);
    }

    function _authorizeUpgrade(
        address impl
    ) internal onlyRole(DEVOPS_ROLE) {
        emitter.emitTermContractUpgraded(address(this), impl);
    }

    // ERC20 implementation
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0), "ERC20: transfer to zero");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[account] += amount;
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from zero");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner][spender] = amount;
    }

    // ERC20Permit implementation
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, structHash));
        address signer = ecrecover(digest, v, r, s);
        require(signer == owner, "ERC20Permit: invalid signature");
        _approve(owner, spender, value);
    }

    // AccessControl implementation
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function _grantRole(bytes32 role, address account) internal {
        _roles[role][account] = true;
    }

    // UUPS implementation
    function upgradeTo(address newImplementation) external onlyRole(DEVOPS_ROLE) {
        _authorizeUpgrade(newImplementation);
        _implementation = newImplementation;
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable onlyRole(DEVOPS_ROLE) {
        _authorizeUpgrade(newImplementation);
        _implementation = newImplementation;
        (bool success, ) = newImplementation.delegatecall(data);
        require(success, "UUPS: upgrade failed");
    }

    function proxiableUUID() external pure returns (bytes32) {
        return keccak256("PROXIABLE");
    }

    // Errors
    error TermRepoTokenMintingPaused();
    error TermRepoTokenBurningPaused();
    error AlreadyTermContractPaired();
    error MintExposureCapExceeded();
}