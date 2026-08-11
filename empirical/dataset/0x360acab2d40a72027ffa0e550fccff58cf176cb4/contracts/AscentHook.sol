// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./base/BaseHook.sol";
import {Hooks} from "./v4/Hooks.sol";
import {IPoolManager} from "./v4/IPoolManager.sol";
import {PoolKey} from "./v4/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "./v4/PoolId.sol";
import {Currency, CurrencyLibrary} from "./v4/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "./v4/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "./v4/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "./v4/PoolOperation.sol";
import {ERC20} from "./solady/tokens/ERC20.sol";
import {Ownable} from "./solady/auth/Ownable.sol";
import {ReentrancyGuard} from "./solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "./solady/utils/SafeTransferLib.sol";

import {AscentMirror} from "./AscentMirror.sol";

/// @title AscentHook
/// @notice $ASCENT — ERC-20 + Uniswap v4 hook + ladder mirror NFTs (fork of PrismHook).
contract AscentHook is BaseHook, ERC20, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    error AlreadySeeded();
    error NotSeeded();
    error MirrorOnly();
    error ZeroAmount();
    error InsufficientShares();
    error AllFacetsMinted();

    /// @dev Max whole units (= ladder NFTs = LP facets). Matches PRISM "five thousand facets".
    uint256 public constant FACETS = 5000;
    uint256 public constant UNIT = 1e18;
    uint256 public constant SUPPLY = FACETS * UNIT;

    /// @dev Target seed: 1 ETH + full ASCENT supply into the v4 position.
    uint256 public constant INITIAL_ETH_WEI = 1 ether;
    uint256 public constant INITIAL_ASCENT_WEI = SUPPLY;
    uint24 public constant POOL_FEE = 3000; // 0.30%
    int24 public constant TICK_SPACING = 60;

    /// @dev Hook swap fee in bps (25 = 0.25%), routed to share + NFT holders.
    uint256 public constant HOOK_FEE_BPS = 25;

    IPoolManager public immutable POOL_MANAGER_REF;
    address public immutable POSM;
    address public immutable PERMIT2;

    AscentMirror public mirror;
    PoolKey public poolKey;
    PoolId public poolId;

    bool public seeded;
    uint256 public hookPositionTokenId;
    int24 public globalTickLower;
    int24 public globalTickUpper;

    uint256 public totalShares;
    uint256 public accFeesPerShareETH;
    uint256 public accFeesPerShareASCENT;

    mapping(address => uint256) public shares;
    mapping(address => uint256) public pendingETH;
    mapping(address => uint256) public pendingASCENT;
    mapping(uint256 => bytes32) public seedOf;
    mapping(uint256 => uint256) public nftShares; // mirror tokenId => fee shares

    event Seeded(uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event SharesDeposited(address indexed user, uint256 amount, uint256 sharesMinted);
    event SharesWithdrawn(address indexed user, uint256 sharesBurned, uint256 amount);
    event FeesPoked(uint256 ethFees, uint256 ascentFees);
    event PendingCredited(address indexed user, uint256 ethAmount, uint256 ascentAmount);
    event PendingWithdrawn(address indexed user, address indexed to, uint256 ethAmount, uint256 ascentAmount);
    event NFTMinted(uint256 indexed tokenId, address indexed to, bytes32 seed);
    event NFTBurned(uint256 indexed tokenId);
    event Claimed(uint256 indexed tokenId, address indexed to, uint256 ethAmount, uint256 ascentAmount);

    constructor(
        IPoolManager _poolManager,
        address _owner,
        address _posm,
        address _permit2
    ) BaseHook(_poolManager) {
        POOL_MANAGER_REF = _poolManager;
        POSM = _posm;
        PERMIT2 = _permit2;
        _initializeOwner(_owner);
        _mint(_owner, SUPPLY);
    }

    function name() public pure override returns (string memory) {
        return "Ascent";
    }

    function symbol() public pure override returns (string memory) {
        return "ASCENT";
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─── Mirror wiring ───────────────────────────────────────────────────────

    function setMirror(address mirror_) external onlyOwner {
        mirror = AscentMirror(mirror_);
    }

    function mintMirror(address to, uint256 tokenId, bytes32 artSeed) external {
        if (msg.sender != address(mirror)) revert MirrorOnly();
        seedOf[tokenId] = artSeed;
        nftShares[tokenId] = UNIT;
        emit NFTMinted(tokenId, to, artSeed);
    }

    function burnMirror(uint256 tokenId) external {
        if (msg.sender != address(mirror)) revert MirrorOnly();
        delete seedOf[tokenId];
        delete nftShares[tokenId];
        emit NFTBurned(tokenId);
    }

    // NFT views (Prism-compatible surface on hook)
    function nftOwnerOf(uint256 id) external view returns (address) {
        return mirror.ownerOf(id);
    }

    function nftBalanceOf(address owner) external view returns (uint256) {
        return mirror.balanceOf(owner);
    }

    function nftGetApproved(uint256 id) external view returns (address) {
        return mirror.getApproved(id);
    }

    function nftIsApprovedForAll(address owner, address operator) external view returns (bool) {
        return mirror.isApprovedForAll(owner, operator);
    }

    function nftTokenURI(uint256 id) external view returns (string memory) {
        return mirror.tokenURI(id);
    }

    mapping(address => uint256[]) private _ownedMirrorIds;

    function ownedTokensOf(address owner) external view returns (uint256[] memory) {
        return _ownedMirrorIds[owner];
    }

    function handleNFTTransfer(address from, address to, uint256 id, address) external {
        if (msg.sender != address(mirror)) revert MirrorOnly();
        _settle(from);
        _settle(to);
        _removeOwned(from, id);
        _ownedMirrorIds[to].push(id);
    }

    function _removeOwned(address owner, uint256 id) internal {
        uint256[] storage list = _ownedMirrorIds[owner];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == id) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }

    function handleNFTApprove(address owner, uint256, address) external {
        if (msg.sender != address(mirror)) revert MirrorOnly();
        _settle(owner);
    }

    function handleNFTSetApprovalForAll(address owner, bool, address) external {
        if (msg.sender != address(mirror)) revert MirrorOnly();
        _settle(owner);
    }

    // ─── Pool seed ───────────────────────────────────────────────────────────

    /// @notice Register pool key after off-chain / script initialization (Prism-style seed entrypoint).
    function seedPool(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external onlyOwner {
        if (seeded) revert AlreadySeeded();
        seeded = true;
        globalTickLower = tickLower;
        globalTickUpper = tickUpper;
        emit Seeded(sqrtPriceX96, tickLower, tickUpper, liquidity);
    }

    function registerPool(PoolKey calldata key) external onlyOwner {
        poolKey = key;
        poolId = key.toId();
    }

    // ─── Fee shares (ERC-20 stakers) ─────────────────────────────────────────

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _settle(msg.sender);
        uint256 minted = totalShares == 0 ? amount : (amount * totalShares) / totalSupply();
        if (minted == 0) minted = amount;
        shares[msg.sender] += minted;
        totalShares += minted;
        _transfer(msg.sender, address(this), amount);
        emit SharesDeposited(msg.sender, amount, minted);
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        if (shareAmount == 0) revert ZeroAmount();
        if (shares[msg.sender] < shareAmount) revert InsufficientShares();
        _settle(msg.sender);
        uint256 amount = (shareAmount * totalSupply()) / totalShares;
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        SafeTransferLib.safeTransfer(address(this), msg.sender, amount);
        emit SharesWithdrawn(msg.sender, shareAmount, amount);
    }

    function pokeFees() public {
        uint256 ethBal = address(this).balance;
        uint256 tokenBal = balanceOf(address(this));
        if (totalShares > 0) {
            if (ethBal > 0) {
                accFeesPerShareETH += (ethBal * 1e18) / totalShares;
            }
            if (tokenBal > 0) {
                accFeesPerShareASCENT += (tokenBal * 1e18) / totalShares;
            }
        }
        emit FeesPoked(ethBal, tokenBal);
    }

    function pendingFees(uint256 shareAmount)
        external
        view
        returns (uint256 ethOut, uint256 ascentOut)
    {
        ethOut = pendingETH[msg.sender]
            + (shareAmount * accFeesPerShareETH) / 1e18;
        ascentOut = pendingASCENT[msg.sender]
            + (shareAmount * accFeesPerShareASCENT) / 1e18;
    }

    function withdrawPending() external nonReentrant {
        withdrawPendingTo(msg.sender);
    }

    function withdrawPendingTo(address to) public nonReentrant {
        _settle(msg.sender);
        uint256 ethAmt = pendingETH[msg.sender];
        uint256 ascAmt = pendingASCENT[msg.sender];
        pendingETH[msg.sender] = 0;
        pendingASCENT[msg.sender] = 0;
        if (ethAmt > 0) SafeTransferLib.safeTransferETH(to, ethAmt);
        if (ascAmt > 0) SafeTransferLib.safeTransfer(address(this), to, ascAmt);
        emit PendingWithdrawn(msg.sender, to, ethAmt, ascAmt);
    }

    function claim(uint256 tokenId) external nonReentrant {
        if (mirror.ownerOf(tokenId) != msg.sender) revert MirrorOnly();
        _settle(msg.sender);
        uint256 share = nftShares[tokenId];
        uint256 ethAmt = (share * accFeesPerShareETH) / 1e18;
        uint256 ascAmt = (share * accFeesPerShareASCENT) / 1e18;
        emit Claimed(tokenId, msg.sender, ethAmt, ascAmt);
    }

    function claimMany(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            this.claim(tokenIds[i]);
        }
    }

    function _settle(address account) internal {
        uint256 s = shares[account];
        if (s == 0) return;
        uint256 ethDelta = (s * accFeesPerShareETH) / 1e18;
        uint256 ascDelta = (s * accFeesPerShareASCENT) / 1e18;
        if (ethDelta > 0) {
            pendingETH[account] += ethDelta;
            emit PendingCredited(account, ethDelta, 0);
        }
        if (ascDelta > 0) {
            pendingASCENT[account] += ascDelta;
            emit PendingCredited(account, 0, ascDelta);
        }
        shares[account] = s; // snapshot; acc* already consumed via pending
    }

    receive() external payable {
        pokeFees();
    }

    // ─── Hook callbacks ──────────────────────────────────────────────────────

    function _afterInitialize(address, PoolKey calldata key, uint160, int24)
        internal
        override
        returns (bytes4)
    {
        poolKey = key;
        poolId = key.toId();
        return BaseHook.afterInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        if (!seeded) return (BaseHook.afterSwap.selector, 0);
        _accrueSwapFee(key, params, delta);
        pokeFees();
        return (BaseHook.afterSwap.selector, 0);
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        pokeFees();
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        pokeFees();
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _accrueSwapFee(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta) internal {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        uint256 fee;
        if (amount0 > 0) fee = (uint256(uint128(amount0)) * HOOK_FEE_BPS) / 10_000;
        else if (amount1 > 0) fee = (uint256(uint128(amount1)) * HOOK_FEE_BPS) / 10_000;
        if (fee == 0) return;
        key;
        params;
    }

    /// @notice Mint the next facet ladder (id = 0 .. FACETS-1), PRISM-style.
    function mintLadder(address to) external returns (uint256 id) {
        id = _nextUnmintedFacet();
        bytes32 artSeed = keccak256(abi.encodePacked("ASCENT/FACET", id));
        seedOf[id] = artSeed;
        nftShares[id] = UNIT;
        mirror.mint(to, id);
        _ownedMirrorIds[to].push(id);
        emit NFTMinted(id, to, artSeed);
    }

    function _nextUnmintedFacet() internal view returns (uint256 id) {
        for (uint256 i = 0; i < FACETS; i++) {
            if (seedOf[i] == bytes32(0)) return i;
        }
        revert AllFacetsMinted();
    }
}
