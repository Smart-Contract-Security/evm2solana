// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {UnisObject} from "./UnisObject.sol";

interface IPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24  fee;
        int24   tickSpacing;
        address hooks;
    }
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
}

interface IUnisHookAdmin {
    function bindObject(address obj, address pool0, address pool1, uint24 fee, int24 tickSpacing) external;
}

/// @title UnisFactory - permissionless forge for Objectized Assets
/// @notice Anyone may call `forge` with an ETH fee. The factory deploys a
///         fresh UnisObject, initialises a V4 pool whose hook is the
///         protocol's shared UnisHook, and notifies the hook so it can route
///         skim revenue to this asset's creator.
contract UnisFactory {
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    uint24  public constant DYNAMIC_FEE  = 0x800000;
    int24   public constant TICK_SPACING = 60;
    address public constant ETH_CURRENCY = address(0);

    address public admin;
    address public treasury;     // UnisToken contract (also receives ETH via receive())
    address public renderer;
    address public hook;

    uint256 public forgeFee = 0.05 ether;
    uint256 public minSupply = 1_000 * 1e18;
    uint256 public maxSupply = 1_000_000_000 * 1e18;

    address[] public allObjects;
    mapping(address => bool)    public isObject;
    mapping(bytes32 => address) public objectByNameHash;
    mapping(address => address) public creatorOf;

    event ObjectForged(
        address indexed object,
        address indexed creator,
        string  name,
        string  symbol,
        uint256 supply,
        bytes32 paletteId,
        bytes32 poolId
    );
    event ForgeFeeSet(uint256 prev, uint256 next);
    event SupplyBoundsSet(uint256 minSup, uint256 maxSup);
    event RendererSet(address indexed prev, address indexed next);
    event HookSet(address indexed prev, address indexed next);
    event TreasurySet(address indexed prev, address indexed next);
    event AdminPassed(address indexed prev, address indexed next);

    error NotAdmin();
    error FeeTooLow();
    error NameTooLong();
    error SymbolTooLong();
    error NameTaken();
    error SupplyOutOfBounds();
    error ZeroAddress();
    error EthForwardFailed();

    modifier onlyAdmin() { if (msg.sender != admin) revert NotAdmin(); _; }

    constructor(address _admin, address _treasury, address _renderer, address _hook) {
        if (_admin == address(0) || _treasury == address(0)) revert ZeroAddress();
        admin    = _admin;
        treasury = _treasury;
        renderer = _renderer;
        hook     = _hook;
    }

    function objectCount() external view returns (uint256) { return allObjects.length; }

    /// @notice Forge a new Objectized Asset. Caller becomes the creator and
    ///         receives the full supply (intent: caller seeds the LP afterwards).
    /// @param  name_      ERC-20 name (<= 24 chars)
    /// @param  symbol_    ERC-20 symbol (<= 10 chars)
    /// @param  supply     total supply (between minSupply and maxSupply, including 18 decimals)
    /// @param  paletteId  bytes32 controlling the renderer's palette for this asset
    /// @param  sqrtPriceX96 initial sqrt price for the V4 pool (Q64.96)
    function forge(
        string calldata name_,
        string calldata symbol_,
        uint256 supply,
        bytes32 paletteId,
        uint160 sqrtPriceX96
    ) external payable returns (address obj, bytes32 poolId) {
        if (msg.value < forgeFee)                          revert FeeTooLow();
        if (bytes(name_).length == 0 || bytes(name_).length > 24)   revert NameTooLong();
        if (bytes(symbol_).length == 0 || bytes(symbol_).length > 10) revert SymbolTooLong();
        if (supply < minSupply || supply > maxSupply)      revert SupplyOutOfBounds();

        bytes32 nh = keccak256(bytes(name_));
        if (objectByNameHash[nh] != address(0))            revert NameTaken();

        obj = address(new UnisObject(
            name_,
            symbol_,
            supply,
            paletteId,
            msg.sender,
            address(this),
            renderer,
            hook
        ));

        allObjects.push(obj);
        isObject[obj]            = true;
        objectByNameHash[nh]     = obj;
        creatorOf[obj]           = msg.sender;

        // V4 pool: ETH = currency0 (address(0) is always lowest)
        (address c0, address c1) = ETH_CURRENCY < obj ? (ETH_CURRENCY, obj) : (obj, ETH_CURRENCY);
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0:   c0,
            currency1:   c1,
            fee:         DYNAMIC_FEE,
            tickSpacing: TICK_SPACING,
            hooks:       hook
        });
        IPoolManager(POOL_MANAGER).initialize(key, sqrtPriceX96);

        // Bind the asset to the hook so it can route skim revenue
        if (hook != address(0)) {
            IUnisHookAdmin(hook).bindObject(obj, c0, c1, DYNAMIC_FEE, TICK_SPACING);
        }

        // poolId is the keccak hash V4 uses internally; recomputed here for the event
        poolId = keccak256(abi.encode(key));

        // Open trading on the new object (LP add will happen post-forge)
        UnisObject(obj).openTrading();

        // Forward ETH fee to treasury
        if (msg.value > 0) {
            (bool ok,) = payable(treasury).call{value: msg.value}("");
            if (!ok) revert EthForwardFailed();
        }

        emit ObjectForged(obj, msg.sender, name_, symbol_, supply, paletteId, poolId);
    }

    // ---- admin ----

    function setForgeFee(uint256 next) external onlyAdmin {
        emit ForgeFeeSet(forgeFee, next);
        forgeFee = next;
    }

    function setSupplyBounds(uint256 minSup, uint256 maxSup) external onlyAdmin {
        require(minSup > 0 && maxSup >= minSup, "bad bounds");
        minSupply = minSup;
        maxSupply = maxSup;
        emit SupplyBoundsSet(minSup, maxSup);
    }

    function setRenderer(address r) external onlyAdmin {
        if (r == address(0)) revert ZeroAddress();
        emit RendererSet(renderer, r);
        renderer = r;
    }

    function setHook(address h) external onlyAdmin {
        if (h == address(0)) revert ZeroAddress();
        emit HookSet(hook, h);
        hook = h;
    }

    function setTreasury(address t) external onlyAdmin {
        if (t == address(0)) revert ZeroAddress();
        emit TreasurySet(treasury, t);
        treasury = t;
    }

    function passAdmin(address next) external onlyAdmin {
        if (next == address(0)) revert ZeroAddress();
        emit AdminPassed(admin, next);
        admin = next;
    }
}
