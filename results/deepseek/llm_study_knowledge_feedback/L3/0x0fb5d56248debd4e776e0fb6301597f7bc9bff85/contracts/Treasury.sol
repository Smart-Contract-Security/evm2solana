// SPDX-License-Identifier: MIT

import {AccountMeta} from 'solana';

interface IAccessController {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function TREASURY_MANAGER_ROLE() external view returns (bytes32);
    function PARAM_MANAGER_ROLE() external view returns (bytes32);
    function ROUTER_ROLE() external view returns (bytes32);
}

interface IAssetRegistry {
    // minimal stub
}

interface IVault {
    function asset() external view returns (address);
    function seedInventory(uint64 amount) external;
    function withdrawInventory(uint64 amount, address recipient) external;
}

interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint64 amountIn;
        uint64 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external returns (uint64);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
    function burn(uint64 amount) external;
}

contract Treasury {
    uint64 public constant BPS_DENOM = 10_000;

    address public access;
    address public registry;

    // ------------------- buyback config -------------------
    address public houseToken;
    address public swapRouter;

    uint16 public buybackBps = 10_000;

    mapping(address => bytes) public buybackPath;

    mapping(address => uint64) public pendingBuyback;

    uint64 public totalHouseBurned;

    // ------------------- events -------------------
    event ProtocolFeeReceived(address indexed token, uint64 amount, uint64 toBuyback, address from);
    event BuybackExecuted(address indexed stable, uint64 stableIn, uint64 houseBurned, address indexed caller);
    event FundsWithdrawn(address indexed token, address indexed to, uint64 amount);
    event InventorySeeded(address indexed vault, uint64 amount);
    event InventoryPulled(address indexed vault, uint64 amount);
    event BuybackBpsUpdated(uint16 newBps);
    event BuybackPathUpdated(address indexed stable, bytes path);
    event SwapRouterUpdated(address newRouter);
    event HouseTokenSet(address house);

    modifier onlyTreasury() {
        require(IAccessController(access).hasRole(IAccessController(access).TREASURY_MANAGER_ROLE(), tx.accounts.dataAccount.key), "NotAuthorized");
        _;
    }

    modifier onlyParam() {
        require(IAccessController(access).hasRole(IAccessController(access).PARAM_MANAGER_ROLE(), tx.accounts.dataAccount.key), "NotAuthorized");
        _;
    }

    modifier onlyRouter() {
        require(IAccessController(access).hasRole(IAccessController(access).ROUTER_ROLE(), tx.accounts.dataAccount.key), "OnlyRouter");
        _;
    }

    constructor(address access_, address registry_) {
        require(access_ != address(0) && registry_ != address(0), "ZeroAddress");
        access = access_;
        registry = registry_;
    }

    // ===================================================================
    //   ADMIN / PARAM
    // ===================================================================

    function setHouseToken(address house) external onlyParam {
        require(house != address(0), "ZeroAddress");
        require(houseToken == address(0), "InvalidParam");
        houseToken = house;
        emit HouseTokenSet(house);
    }

    function setSwapRouter(address router) external onlyParam {
        require(router != address(0), "ZeroAddress");
        swapRouter = router;
        emit SwapRouterUpdated(router);
    }

    function setBuybackBps(uint16 newBps) external onlyParam {
        require(newBps <= BPS_DENOM, "InvalidParam");
        buybackBps = newBps;
        emit BuybackBpsUpdated(newBps);
    }

    function setBuybackPath(address stable, bytes calldata path) external onlyParam {
        require(stable != address(0), "ZeroAddress");
        require(path.length != 0, "InvalidParam");
        buybackPath[stable] = path;
        emit BuybackPathUpdated(stable, path);
    }

    // ===================================================================
    //   FEE INTAKE — called by Router
    // ===================================================================

    function receiveProtocolFee(address token, uint64 amount, address from) external onlyRouter {
        if (amount == 0) return;
        IERC20(token).transferFrom(from, address(this), amount);
        uint64 toBuyback = (amount * buybackBps) / BPS_DENOM;
        if (toBuyback > 0) pendingBuyback[token] += toBuyback;
        emit ProtocolFeeReceived(token, amount, toBuyback, from);
    }

    // ===================================================================
    //   BUYBACK + BURN — permissionless
    // ===================================================================

    function executeBuyback(address stable, uint64 amountIn, uint64 minHouseOut)
        external
        returns (uint64 houseBurned)
    {
        require(houseToken != address(0) && swapRouter != address(0), "InvalidParam");
        bytes memory path = buybackPath[stable];
        require(path.length != 0, "InvalidParam");

        uint64 pending = pendingBuyback[stable];
        require(pending != 0, "ZeroAmount");
        if (amountIn == 0 || amountIn > pending) amountIn = pending;

        pendingBuyback[stable] = pending - amountIn;

        IERC20(stable).approve(swapRouter, amountIn);
        houseBurned = ISwapRouter(swapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minHouseOut
            })
        );

        if (houseBurned > 0) {
            IERC20(houseToken).burn(houseBurned);
            totalHouseBurned += houseBurned;
        }
        emit BuybackExecuted(stable, amountIn, houseBurned, tx.accounts.dataAccount.key);
    }

    // ===================================================================
    //   OPS TREASURY (non-buyback portion)
    // ===================================================================

    function withdraw(address token, address to, uint64 amount) external onlyTreasury {
        require(to != address(0), "ZeroAddress");
        uint64 bal = IERC20(token).balanceOf(address(this));
        uint64 free = bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
        require(amount <= free, "InsufficientExcess");
        IERC20(token).transfer(to, amount);
        emit FundsWithdrawn(token, to, amount);
    }

    // ===================================================================
    //   VAULT INVENTORY OPS
    // ===================================================================

    function seedVaultInventory(address vault, uint64 amount) external onlyTreasury {
        address asset = IVault(vault).asset();
        uint64 bal = IERC20(asset).balanceOf(address(this));
        uint64 free = bal > pendingBuyback[asset] ? bal - pendingBuyback[asset] : 0;
        require(amount <= free, "InsufficientExcess");
        IERC20(asset).approve(vault, amount);
        IVault(vault).seedInventory(amount);
        emit InventorySeeded(vault, amount);
    }

    function pullVaultInventory(address vault, uint64 amount) external onlyTreasury {
        IVault(vault).withdrawInventory(amount, address(this));
        emit InventoryPulled(vault, amount);
    }

    // ===================================================================
    //   VIEWS
    // ===================================================================

    function balance(address token) external view returns (uint64) {
        return IERC20(token).balanceOf(address(this));
    }

    function freeBalance(address token) external view returns (uint64) {
        uint64 bal = IERC20(token).balanceOf(address(this));
        return bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
    }
}