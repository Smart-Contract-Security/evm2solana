// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Solang on Solana does not support importing external Solidity interfaces directly.
// We define minimal stubs inline to satisfy the compiler.
// In a real deployment, these would be replaced with proper Solana-compatible interfaces.

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
    function seedInventory(uint256 amount) external;
    function withdrawInventory(uint256 amount, address to) external;
}

interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
}

// Minimal IERC20 stub for Solana
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Minimal SafeERC20 library stub
library SafeERC20 {
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        bool success = token.transferFrom(from, to, amount);
        require(success, "SafeERC20: transferFrom failed");
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        bool success = token.transfer(to, amount);
        require(success, "SafeERC20: transfer failed");
    }

    function forceApprove(IERC20 token, address spender, uint256 amount) internal {
        bool success = token.approve(spender, amount);
        require(success, "SafeERC20: approve failed");
    }
}

// Minimal ERC20Burnable stub
contract ERC20Burnable {
    function burn(uint256 amount) public virtual {
        // Stub: actual implementation would be provided by the token contract
    }
}

// Errors library stub
library Errors {
    // Custom errors are not supported on Solana; we use string revert reasons instead.
    // The library is kept for interface compatibility but errors are replaced with require strings.
}

// ReentrancyGuard stub for Solana (Solang does not support OpenZeppelin's ReentrancyGuard natively)
contract ReentrancyGuard {
    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
}

contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOM = 10_000;

    address public immutable access;
    address public immutable registry;

    address public houseToken;
    address public swapRouter;

    uint16 public buybackBps = 10_000;

    mapping(address => bytes) public buybackPath;

    mapping(address => uint256) public pendingBuyback;

    uint256 public totalHouseBurned;

    event ProtocolFeeReceived(address indexed token, uint256 amount, uint256 toBuyback, address from);
    event BuybackExecuted(address indexed stable, uint256 stableIn, uint256 houseBurned, address indexed caller);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event InventorySeeded(address indexed vault, uint256 amount);
    event InventoryPulled(address indexed vault, uint256 amount);
    event BuybackBpsUpdated(uint16 newBps);
    event BuybackPathUpdated(address indexed stable, bytes path);
    event SwapRouterUpdated(address newRouter);
    event HouseTokenSet(address house);

    modifier onlyTreasury() {
        require(IAccessController(access).hasRole(IAccessController(access).TREASURY_MANAGER_ROLE(), msg.sender), "NotAuthorized");
        _;
    }

    modifier onlyParam() {
        require(IAccessController(access).hasRole(IAccessController(access).PARAM_MANAGER_ROLE(), msg.sender), "NotAuthorized");
        _;
    }

    modifier onlyRouter() {
        require(IAccessController(access).hasRole(IAccessController(access).ROUTER_ROLE(), msg.sender), "OnlyRouter");
        _;
    }

    constructor(address access_, address registry_) {
        require(access_ != address(0) && registry_ != address(0), "ZeroAddress");
        access = access_;
        registry = registry_;
    }

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

    function receiveProtocolFee(address token, uint256 amount, address from) external onlyRouter {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(from, address(this), amount);
        uint256 toBuyback = (amount * buybackBps) / BPS_DENOM;
        if (toBuyback > 0) pendingBuyback[token] += toBuyback;
        emit ProtocolFeeReceived(token, amount, toBuyback, from);
    }

    function executeBuyback(address stable, uint256 amountIn, uint256 minHouseOut)
        external
        nonReentrant
        returns (uint256 houseBurned)
    {
        require(houseToken != address(0) && swapRouter != address(0), "InvalidParam");
        bytes memory path = buybackPath[stable];
        require(path.length != 0, "InvalidParam");

        uint256 pending = pendingBuyback[stable];
        require(pending != 0, "ZeroAmount");
        if (amountIn == 0 || amountIn > pending) amountIn = pending;

        pendingBuyback[stable] = pending - amountIn;

        IERC20(stable).forceApprove(swapRouter, amountIn);
        houseBurned = ISwapRouter(swapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minHouseOut
            })
        );

        if (houseBurned > 0) {
            ERC20Burnable(houseToken).burn(houseBurned);
            totalHouseBurned += houseBurned;
        }
        emit BuybackExecuted(stable, amountIn, houseBurned, msg.sender);
    }

    function withdraw(address token, address to, uint256 amount) external onlyTreasury nonReentrant {
        require(to != address(0), "ZeroAddress");
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 free = bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
        require(amount <= free, "InsufficientExcess");
        IERC20(token).safeTransfer(to, amount);
        emit FundsWithdrawn(token, to, amount);
    }

    function seedVaultInventory(address vault, uint256 amount) external onlyTreasury nonReentrant {
        IVault v = IVault(vault);
        address asset = v.asset();
        uint256 bal = IERC20(asset).balanceOf(address(this));
        uint256 free = bal > pendingBuyback[asset] ? bal - pendingBuyback[asset] : 0;
        require(amount <= free, "InsufficientExcess");
        IERC20(asset).approve(vault, amount);
        v.seedInventory(amount);
        emit InventorySeeded(vault, amount);
    }

    function pullVaultInventory(address vault, uint256 amount) external onlyTreasury nonReentrant {
        IVault(vault).withdrawInventory(amount, address(this));
        emit InventoryPulled(vault, amount);
    }

    function balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function freeBalance(address token) external view returns (uint256) {
        uint256 bal = IERC20(token).balanceOf(address(this));
        return bal > pendingBuyback[token] ? bal - pendingBuyback[token] : 0;
    }
}